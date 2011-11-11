#!/bin/bash
# Script for downloading the contents of one splinder.com profile.
# (Not including the blog.)
#
# Usage:   dld-profile.sh ${USERNAME}
#

VERSION="20111111.01"

# this script needs wget-warc, which you can find on the ArchiveTeam wiki.

WGET_WARC=./wget-warc
if [ ! -x $WGET_WARC ]
then
  echo "./wget-warc not found."
  exit 3
fi

USER_AGENT="Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/533.20.25 (KHTML, like Gecko) Version/5.0.4 Safari/533.20.27"

username="$1"
enc_username=$( echo "$username" | tr '|&;()<>./\\*' '_' )
userdir=$( printf "data/%s/%s/%s/%q" "${enc_username:0:1}" "${enc_username:0:2}" "${enc_username:0:3}" "${username}" )

if [[ -f "${userdir}/.incomplete" ]]
then
  echo "  Deleting incomplete result for ${username}"
  rm -rf "${userdir}"
fi

if [[ -d "${userdir}" ]]
then
  echo "  Already downloaded ${username}"
  exit 2
fi

mkdir -p "${userdir}"
touch "${userdir}/.incomplete"

echo "  Downloading ${username} profile"

echo -n "   - Downloading profile HTML pages..."
$WGET_WARC -U "${USER_AGENT}" -e "robots=off" \
    -nv -o "$userdir/wget-phase-1.log" \
    --directory-prefix="$userdir/files/" \
    --warc-file="$userdir/splinder.com-${enc_username}-html" \
    --warc-max-size=inf \
    --warc-header="operator: Archive Team" \
    --warc-header="splinder-dld-script-version: ${VERSION}" \
    --warc-header="splinder-username: ${username}" \
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
    "http://www.splinder.com/profile/${username}/" \
    "http://www.splinder.com/ajax.php?type=counter&op=profile&profile=${username}" \
    "http://www.splinder.com/profile/${username}/friends/" \
    "http://www.splinder.com/profile/${username}/friendof/" \
    "http://www.splinder.com/profile/${username}/blogs/" \
    "http://www.splinder.com/mediablog/${username}/"
result=$?
if [ $result -ne 0 ] && [ $result -ne 6 ] && [ $result -ne 8 ]
then
  echo " ERROR ($result)."
  exit 1
fi
echo " done."

echo -n "   - Parsing profile HTML to extract media urls..."
find "$userdir/files/" -name "*.html" \
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
      --warc-file="$userdir/splinder.com-${enc_username}-media" \
      --warc-max-size=inf \
      --warc-header="operator: Archive Team" \
      --warc-header="splinder-dld-script-version: ${VERSION}" \
      --warc-header="splinder-username: ${username}" \
      -i "$userdir/media-urls.txt"
  result=$?
  if [ $result -ne 0 ] && [ $result -ne 6 ] && [ $result -ne 8 ]
  then
    echo " ERROR ($result)."
    exit 1
  fi
fi
echo " done."

blog_domains=$(
  grep -oE '<a href="http://[^." ]+\.splinder.com' \
       "${userdir}/files/www.splinder.com/profile/${username}/blogs/index.html" \
    | cut -c 17- \
    | grep -vE "(edit|journal|manuale|www).splinder.com"
)
for blog_domain in $blog_domains
do
  echo -n "   - Downloading blog from ${blog_domain}..."
  $WGET_WARC -U "${USER_AGENT}" -e "robots=off" \
      -nv -o "$userdir/wget-phase-3-${blog_domain}.log" \
      --directory-prefix="$userdir/files/" \
      --warc-file="$userdir/splinder.com-${enc_username}-blog-${blog_domain}" \
      --warc-max-size=inf \
      --warc-header="operator: Archive Team" \
      --warc-header="splinder-dld-script-version: ${VERSION}" \
      --warc-header="splinder-username: ${username}" \
      -r -l inf --no-remove-listing \
      --no-timestamping \
      --page-requisites --trust-server-names \
      --span-hosts \
      --domains="${blog_domain},files.splinder.com,www.splinder.com,syndication.splinder.com" \
      --exclude-directories="/users,/media,/node,/profile,/mediablog,/community,/user,/night,/home,/mysearch,/online,/trackback,/myblog/post,/myblog/posts,/myblog/tags,/myblog/tag,/myblog/view,/myblog/latest,/myblog/subscribe,/myblog/comment/reply,/myblog/comments/latest,/post,/posts" \
      "http://${blog_domain}/"
  result=$?
  if [ $result -ne 0 ] && [ $result -ne 6 ] && [ $result -ne 8 ]
  then
    echo " ERROR ($result)."
    exit 1
  fi
  echo " done."
done

rm -rf "$userdir/files"

echo -n "   - Result: "
./du-helper.sh "$userdir/"

rm "${userdir}/.incomplete"

exit 0



