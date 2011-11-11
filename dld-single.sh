#!/bin/bash
#
# Downloads a single user and tells the tracker it's done.
# This can be handy if dld-client.sh failed and you'd like
# to retry the user.
#
# Usage:   dld-single.sh ${YOURALIAS} it:${USERNAME}
#

youralias="$1"
username="$2"

if [[ ! $youralias =~ ^[-A-Za-z0-9_]+$ ]]
then
  echo "Usage:  $0 {yournick} it:{usertodownload}"
  echo "Run with a nickname with only A-Z, a-z, 0-9, - and _"
  exit 4
fi

if [ -z $username ] || [[ ! $username =~ ^it: ]]
then
  echo "Usage:  $0 {yournick} it:{usertodownload}"
  echo "Provide a username."
  exit 5
fi

VERSION=$( grep 'VERSION=' dld-profile.sh | grep -oE "[-0-9.]+" )

username_without_language=${username/it:/}

if ./dld-profile.sh "$username_without_language"
then
  # complete

  # statistics!
  enc_username=$( echo "$username_without_language" | tr '|&;()<>./\\*' '_' )
  userdir=$( printf "data/%s/%s/%s/%q" "${enc_username:0:1}" "${enc_username:0:2}" "${enc_username:0:3}" "${username_without_language}" )
  bytes_str="{"
  if [[ $( find "${userdir}/" -name "*-blog-*.gz" | wc -l ) -ne 0 ]]
  then
    bytes_str="${bytes_str}\"blogs\":$( ./du-helper.sh -bsc "${userdir}/"*"-blog-"*".warc.gz" | tail -n 1 ),"
  else
    bytes_str="${bytes_str}\"blogs\":0,"
  fi
  bytes_str="${bytes_str}\"html\":$( ./du-helper.sh -bs "${userdir}/"*"-html.warc.gz" ),"
  bytes_str="${bytes_str}\"media\":$( ./du-helper.sh -bs "${userdir}/"*"-media.warc.gz" )"
  bytes_str="${bytes_str}}"

  # some more statistics
  ids=($( cut "${userdir}/media-urls.txt" -c 27- ))
  id=0
  if [[ ${#ids[*]} -gt 0 ]]
  then
    id="${#ids[*]}:${ids[0]}:${ids[${#ids[*]}-1]}"
  fi

  success_str="{\"downloader\":\"${youralias}\",\"user\":\"${username}\",\"bytes\":${bytes_str},\"version\":\"${VERSION}\",\"id\":\"${id}\"}"
  echo "Telling tracker that '${username}' is done."
  resp=$( curl -s -f -d "$success_str" http://splinder.heroku.com/done )
  if [[ "$resp" != "OK" ]]
  then
    echo "ERROR contacting tracker. Could not mark '$username' done."
    exit 5
  fi
  echo
else
  echo "Error downloading '$username'."
  exit 6
fi

