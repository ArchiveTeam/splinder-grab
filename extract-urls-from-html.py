from BeautifulSoup import BeautifulSoup
import fileinput
import re

class UrlCollector:
  FILES_URL_RE = re.compile("http://files.u?s?.?splinder.com/[a-z0-9_\.]+")
  FILE_JPG_URL_RE = re.compile("^(http://files.u?s?.?splinder.com/[a-z0-9]+)[_a-z]*(\.(jpg|gif|png))$")
  FILE_MP3_URL_RE = re.compile("^(http://files.u?s?.?splinder.com/[a-z0-9]+)[_a-z]*(\.mp3)$")
  FILE_FLV_URL_RE = re.compile("^(http://files.u?s?.?splinder.com/[a-z0-9]+)[_a-z]*(\.flv)$")

  def __init__(self):
    self.urls = set()

  def process(self, soup):
    for singolo in soup.findAll('div', 'singolo-media'):
      for img in singolo.findAll('img', attrs={'src' : self.FILES_URL_RE}):
        self.addUrlsFromString(img['src'])

      for a in singolo.findAll('a', attrs={'href' : self.FILES_URL_RE}):
        self.addUrlsFromString(a['href'])

      for param in singolo.findAll('param', attrs={'name' : ('flashvars','movie')}):
        self.addUrlsFromString(param['value'])

    for mediaFooter in soup.findAll('div', 'media-footer'):
      for img in mediaFooter.findAll('img', attrs={'src' : self.FILES_URL_RE}):
        self.addUrlsFromString(img['src'])

    for profilo in soup.findAll('div', 'profilo'):
      for img in profilo.findAll('img', attrs={'src' : self.FILES_URL_RE}):
        self.addUrlsFromString(img['src'])

  def addUrlsFromString(self, string):
    for url in re.findall(self.FILES_URL_RE, string):
      self.addUrl(url)

  def addUrl(self, url):
    self.urls.add(url)

    m = re.match(self.FILE_JPG_URL_RE, url)
    if m:
      for size in ('_square','_medium','_thumbnail',''):
        self.urls.add(''.join((m.group(1), size, m.group(2))))

    m = re.match(self.FILE_MP3_URL_RE, url)
    if m:
      for size in ('_thumbnail',''):
        self.urls.add(''.join((m.group(1), size, m.group(2))))

    m = re.match(self.FILE_FLV_URL_RE, url)
    if m:
      self.urls.add(''.join((m.group(1), '.flv')))
      for size in ('_square','_small','_thumbnail',''):
        self.urls.add(''.join((m.group(1), size, '.jpg')))

  def __iter__(self):
    return self.urls.__iter__()


urls = UrlCollector()

for line in fileinput.input():
  f = open(line.strip())
  html = f.read()
  f.close()

  soup = BeautifulSoup(html)
  urls.process(soup)

for url in urls:
  print url

