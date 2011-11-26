#!/usr/bin/env python2.7
# Splinder verification script.
#
# This scripts checks the WARC files for a Splinder user to see if
# there are any errors that make the file incomplete.
#
# To check one profile:
#
#   ./verify-splinder-profile.py <USERDIR>
#
# The script will exit with status 0 if the directory contains a
# valid and complete archive. Status 1 indicates that the user does
# not exist (but that the answer is still valid). Status 2 indicates
# an error that makes the archive incomplete.
#
# To check multiple profiles: pipe the directories you want to check
# the script's standard input, separated by newlines. For example:
#
#   find data/ -mindepth 5 -maxdepth 5 -type d | ./verify-splinder-profile.py
#
# The script will
# check each directory and output result lines starting with a pipe:
#
#   | OK <USERNAME>
#   | NOTFOUND <USERNAME>
#
# indicate that the profile is complete or nonexistent, respectively.
# In the case of an error the script provides one line starting with
# a pipe character and extra details about the error. (Note: It's not
# always possible to determine the username for incomplete profiles.)
#
#
#
# This script currently checks the following:
#
#  1. A full check of the WARC files (is it a valid GZIP file,
#     can every record be extracted and parsed).
#  2. A check for the wget metadata resource records. These records
#     should have been written at the end of each WARC file, so if
#     they aren't there the file is probably incomplete.
#  3. A check of the HTTP error codes, anything that's not
#     200, 301, 302 or 404 is considered a problem.
#  4. A check for HTTP requests without an HTTP response,
#     indicating a network error.
#  5. A check of the blog downloads (is every blog included?).
#  6. A check for splinder_noconn.html urls.
#  7. A check for the 'this site is disabled' 404 page that was
#     returned for some of the US profiles. (There is another 404
#     page for 'this profile does not exist'.)
#

import os
import re
import sys
import zlib

from StringIO import StringIO
from hanzo.warctools import WarcRecord
from hanzo.httptools.messaging import RequestMessage, ResponseMessage

class RecordSequenceException(Exception):
  def __init__(self, value):
    self.parameter = value

  def __str__(self):
    return repr(self.parameter)

class WarcException(Exception):
  def __init__(self, value):
    self.parameter = value

  def __str__(self):
    return repr(self.parameter)
  

class UrlCollector():
  def __init__(self):
    self.url_statuses = {}
    self.blogs = []
    self.resources = set()

  def process_file(self, filename):
    f = WarcRecord.open_archive(filename, gzip="auto")

    for (offset, record, errors) in f.read_records(limit=None):
      if record:
        if record.type=="response":
          self._process_response(record)
        elif record.type=="request":
          self._process_request(record)
        elif record.type=="resource":
          self._process_resource(record)
      elif errors:
        raise WarcException, "Cannot decode WARC: %s" % errors

    self.current_request = None

    f.close()

  def _process_request(self, record):
    self.url_statuses[record.url] = 999

  def _process_resource(self, record):
    self.resources.add(record.url)

  HTTP_STATUS_RE = re.compile("HTTP/1.[01] ([0-9]{3})")
  URL_PROFILE_RE = re.compile("^http://www\.(us\.)?splinder\.com/profile/[^/]+/?$")
  URL_BLOGS_RE = re.compile("^http://www\.(us\.)?splinder\.com/profile/[^/]+/blogs/?$")

  def _process_response(self, record):
    m = self.HTTP_STATUS_RE.match(record.content[1])
    if not m:
      raise WarcException, "Invalid HTTP status line: %s." % record.split("\n")[0]
    status = int(m.group(1))

    self.url_statuses[record.url] = status

    if self.URL_PROFILE_RE.match(record.url):
      self.profile_url = record.url

      if status==404 and "<center><h1>404 Not Found</h1></center>" in record.content[1]:
        # this is the error message us.splinder.com returned while it was down
        status = 998

    if status==200:
      if self.URL_BLOGS_RE.match(record.url):
        # extract blog urls
        self._extract_blog_urls(record)

  BLOG_LINK_RE = re.compile("Blog: <a href=\"http://([^/]+\.(us\.)?splinder\.com)")

  def _extract_blog_urls(self, record):
    for m in self.BLOG_LINK_RE.finditer(record.content[1]):
      self.blogs.append(m.group(1))



EXPECTED_RESOURCES = set([
  'metadata://gnu.org/software/wget/warc/MANIFEST.txt',
  'metadata://gnu.org/software/wget/warc/wget_arguments.txt',
  'metadata://gnu.org/software/wget/warc/wget.log'
])

def test_profile(userdir):
  errors = []

  files = [ f for f in os.listdir(userdir) if f.endswith(".warc.gz") ]

  if not True in [ f.endswith("html.warc.gz") for f in files ]:
    return ("INCOMPLETE-NOHTML", "")

  uc = UrlCollector()

  for f in files:
    try:
      uc.resources = set()
      uc.process_file(os.path.join(userdir, f))
      
      if not EXPECTED_RESOURCES.issubset(uc.resources):
        # this file is not complete
        return ("INCOMPLETE-WARC", f)

    except WarcException as err:
      return ("INVALID-WARC", f, "%s" % err)
    except zlib.error as err:
      return ("INVALID-GZIP", f, "%s" % err)

  if not uc.profile_url:
    return ("INCOMPLETE-NOPROFILE", "")

  for url in uc.url_statuses.iterkeys():
    if url.endswith("splinder_noconn.html"):
      return ("INCOMPLETE-NOCONN", "")

  profile = re.search("splinder\.com/profile/([^/]+)", uc.profile_url).group(1)

  profile_status = uc.url_statuses[uc.profile_url]
  if profile_status == 404:
    return ("NOTFOUND", profile)

  for (url, status) in uc.url_statuses.iteritems():
    if status not in [200, 301, 302, 404]:
      print "HTTP error %d on url %s" % (status, url)
      return ("ERROR", profile, "%d"%status)

  for blog in uc.blogs:
    if not True in [ f.endswith("blog-%s.warc.gz" % blog) for f in files ]:
      print "No WARC for blog %s" % blog
      return ("INCOMPLETE-BLOG", profile, blog)

  return ("OK", profile)


if not sys.argv or len(sys.argv) < 2:
  while True:
    line = sys.stdin.readline()
    if line == None or line.strip()=="":
      break

    userdir = line.strip()
    result = test_profile(userdir)
    if result[0] != "OK":
      print "Error in dir %s" % userdir
    print "| %s" % (" ".join(result))

else:
  userdir = sys.argv[1]

  result = test_profile(userdir)
  print "| %s" % (" ".join(result))

  if result[0]=="OK":
    sys.exit(0)
  elif result[1]=="NOTFOUND":
    sys.exit(1)
  else:
    sys.exit(2)

