#!/bin/bash
#
# Script for downloading the contents of one splinder.com profile.
# (Not including the blog.)
#
# Usage:   dld-profile.sh it ${USERNAME}
#          dld-profile.sh us ${USERNAME}
#

VERSION="20111113.02"

# this script needs wget-warc, which you can find on the ArchiveTeam wiki.

WGET_WARC=./wget-warc
if [ ! -x $WGET_WARC ]
then
  echo "./wget-warc not found."
  exit 3
fi

USER_AGENT="Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/533.20.25 (KHTML, like Gecko) Version/5.0.4 Safari/533.20.27"

if [[ $1 =~ us ]]
then
  country="us"
  domain="us.splinder.com"
else
  country="it"
  domain="splinder.com"
fi

username="$2"
enc_username=$( echo "$username" | tr '|&;()<>./\\*' '_' )
userdir=$( printf "data/%s/%s/%s/%s/%q" "${country}" "${enc_username:0:1}" "${enc_username:0:2}" "${enc_username:0:3}" "${username}" )

filedir="./tmpfs/"${country}/$username
mkdir -p "$filedir"

cleanup()
{
  rm -fr "$filedir"
}

# call cleanup on script exit
trap cleanup EXIT

if [[ -f "${userdir}/.incomplete" ]]
then
  echo "  Deleting incomplete result for ${country}:${username}"
  rm -rf "${userdir}"
fi

if [[ -d "${userdir}" ]]
then
  echo "  Already downloaded ${country}:${username}"
  exit 0
fi

mkdir -p "${userdir}"
touch "${userdir}/.incomplete"

echo "  Downloading ${country}:${username} profile"

echo -n "   - Downloading profile HTML pages..."
$WGET_WARC -U "${USER_AGENT}" -e "robots=off" \
    -nv -o "$userdir/wget-phase-1.log" \
    --directory-prefix="$filedir/" \
    --warc-file="$userdir/${domain}-${enc_username}-html" \
    --warc-max-size=inf \
    --warc-header="operator: Archive Team" \
    --warc-header="splinder-dld-script-version: ${VERSION}" \
    --warc-header="splinder-username: ${domain}, ${username}" \
    -r -l inf --no-remove-listing \
    --no-timestamping \
    --trust-server-names \
    --adjust-extension \
    -I "/profile/${username}/friends" \
    -I "/profile/${username}/friendof" \
    -I "/profile/${username}/blogs" \
    -I "/mediablog/${username}" \
    -I "/media/comment/list/" \
    -R "sizes" \
    "http://www.${domain}/profile/${username}/" \
    "http://www.${domain}/ajax.php?type=counter&op=profile&profile=${username}" \
    "http://www.${domain}/profile/${username}/friends/" \
    "http://www.${domain}/profile/${username}/friendof/" \
    "http://www.${domain}/profile/${username}/blogs/" \
    "http://www.${domain}/mediablog/${username}/"
result=$?
if [ $result -ne 0 ] && [ $result -ne 4 ] && [ $result -ne 6 ] && [ $result -ne 8 ]
then
  echo " ERROR ($result)."
  exit 1
elif [ $result -eq 8 ]
then
  echo " done, with HTTP errors."
  # check for 502, 504 errors
  echo -n "   - Checking for important 502, 504 errors..."
  if grep -q "ERROR 50" "${userdir}/wget-phase-1.log"
  then
    echo " errors found."
    exit 8
  fi
  echo " none found."
elif [ $result -eq 4 ]
then
  echo " done, with network errors."
  exit 4
else
  echo " done."
fi

echo -n "   - Parsing profile HTML to extract media urls..."
find "$filedir/" -name "*.html" \
  | python extract-urls-from-html.py \
  > "$userdir/media-urls.txt"
echo " done."

num_urls=$(cat "$userdir/media-urls.txt" | wc -l)

echo -n "   - Downloading ${num_urls} media files..."
if [[ $num_urls -ne 0 ]]
then
  $WGET_WARC -U "${USER_AGENT}" -e "robots=off" \
      -nv -o "$userdir/wget-phase-2.log" \
      -O /dev/null \
      --warc-file="$userdir/${domain}-${enc_username}-media" \
      --warc-max-size=inf \
      --warc-header="operator: Archive Team" \
      --warc-header="splinder-dld-script-version: ${VERSION}" \
      --warc-header="splinder-username: ${domain}, ${username}" \
      -i "$userdir/media-urls.txt"
  result=$?
  if [ $result -ne 0 ] && [ $result -ne 4 ] && [ $result -ne 6 ] && [ $result -ne 8 ]
  then
    echo " ERROR ($result)."
    exit 1
  elif [ $result -eq 8 ]
  then
    echo " done, with HTTP errors."
    # check for 502, 504 errors
    echo -n "   - Checking for important 502, 504 errors..."
    if grep -q "ERROR 50" "${userdir}/wget-phase-2.log"
    then
      echo " errors found."
      exit 8
    fi
    echo " none found."
  elif [ $result -eq 4 ]
  then
    echo " done, with network errors."
    exit 4
  else
    echo " done."
  fi
else
  echo " done."
fi

if [ -f "${filedir}/www.${domain}/profile/${username}/blogs/index.html" ]
then
  grep -oE '<a href="http://[^." ]+\.splinder.com' \
       "${filedir}/www.${domain}/profile/${username}/blogs/index.html" \
     | cut -c 17- \
     | grep -vE "(edit|journal|manuale|www).splinder.com" \
     > "${userdir}/blogs.txt"
fi

if [ -f "${filedir}/www.${domain}/profile/${username}/blogs/index.html" ]
then
  blog_domains=$(
    grep Blog: "${filedir}/www.${domain}/profile/${username}/blogs/index.html" \
      | grep -oE "<a href=\"http://[^.\" ]+\.${domain}" \
      | cut -c 17-
  )
  for blog_domain in $blog_domains
  do
    echo -n "   - Downloading blog from ${blog_domain}..."
    $WGET_WARC -U "${USER_AGENT}" -e "robots=off" \
        -nv -o "$userdir/wget-phase-3-${blog_domain}.log" \
        --directory-prefix="$filedir/" \
        --warc-file="$userdir/${domain}-${enc_username}-blog-${blog_domain}" \
        --warc-max-size=inf \
        --warc-header="operator: Archive Team" \
        --warc-header="splinder-dld-script-version: ${VERSION}" \
        --warc-header="splinder-username: ${domain}, ${username}" \
        -r -l inf --no-remove-listing \
        --no-timestamping \
        --page-requisites --trust-server-names \
        --span-hosts \
        --domains="${blog_domain},files.${domain},www.${domain},syndication.${domain}" \
        --exclude-directories="/users,/media,/node,/profile,/mediablog,/community,/user,/night,/home,/mysearch,/online,/trackback,/myblog/post,/myblog/posts,/myblog/tags,/myblog/tag,/myblog/taglist,/myblog/view,/myblog/latest,/myblog/subscribe,/myblog/comment/reply,/myblog/comments/latest,/post,/posts,/book" \
        "http://${blog_domain}/"
    result=$?
    if [ $result -ne 0 ] && [ $result -ne 4 ] && [ $result -ne 6 ] && [ $result -ne 8 ]
    then
      echo " ERROR ($result)."
      exit 1
    elif [ $result -eq 8 ]
    then
      echo " done, with HTTP errors."
      # check for 502, 504 errors
      echo -n "   - Checking for important 502, 504 errors..."
      if grep -q "ERROR 50" "${userdir}/wget-phase-3-${blog_domain}.log"
      then
        echo " errors found."
        exit 8
      fi
      echo " none found."
    elif [ $result -eq 4 ]
    then
      echo " done, with network errors."
      exit 4
    else
      echo " done."
    fi
  done
fi

echo -n "   - Result: "
./du-helper.sh -hs "$userdir/"

rm "${userdir}/.incomplete"

exit 0



