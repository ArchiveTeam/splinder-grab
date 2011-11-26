#!/bin/bash
#
# Downloads a single user and tells the tracker it's done.
# This can be handy if dld-client.sh failed and you'd like
# to retry the user.
#
# Usage:   dld-single.sh ${YOURALIAS} it:${USERNAME}
#          dld-single.sh ${YOURALIAS} us:${USERNAME}
#

youralias="$1"
username="$2"

if [[ ! $youralias =~ ^[-A-Za-z0-9_]+$ ]]
then
  echo "Usage:  $0 {yournick} it:{usertodownload}"
  echo "        $0 {yournick} us:{usertodownload}"
  echo "Run with a nickname with only A-Z, a-z, 0-9, - and _"
  exit 4
fi

if [ -z $username ] || [[ ! $username =~ ^(it|us): ]]
then
  echo "Usage:  $0 {yournick} it:{usertodownload}"
  echo "        $0 {yournick} us:{usertodownload}"
  echo "Provide a username."
  exit 5
fi

VERSION=$( grep 'VERSION=' dld-profile.sh | grep -oE "[-0-9.]+" )

if [[ $username =~ ^it: ]]
then
  country=it
  username_without_country=${username/it:/}
  domain="splinder.com"
elif [[ $username =~ ^us: ]]
then
  country=us
  username_without_country=${username/us:/}
  domain="us.splinder.com"
else
  echo "Invalid country."
  exit 5
fi

should_retry=1
tries=0
while [ $should_retry -eq 1 ]
do
  ./dld-profile.sh "$country" "$username_without_country"
  result=$?
  if [ $result -eq 4 ] || [ $result -eq 8 ]
  then
    should_retry=1
  else
    should_retry=0
  fi

  if [ $should_retry -eq 1 ] && [ $tries -lt 5 ]
  then
    echo "Retrying this user."
    tries=$(( tries + 1 ))
  else
    should_retry=0
  fi
done

if [ $result -eq 0 ]
then
  # complete

  # statistics!
  enc_username=$( echo "$username_without_country" | tr '|&;()<>./\\*' '_' )
  userdir=$( printf "data/%s/%s/%s/%s/%q" "$country" "${enc_username:0:1}" "${enc_username:0:2}" "${enc_username:0:3}" "${username_without_country}" )
  bytes_str="{"
  if [[ $( find "${userdir}/" -name "*-media.warc.gz" | wc -l ) -ne 0 ]]
  then
    bytes_str="${bytes_str}\"media\":$( ./du-helper.sh -bsc "${userdir}/"*"-media.warc.gz" | tail -n 1 ),"
  else
    bytes_str="${bytes_str}\"media\":0,"
  fi
  if [[ $( find "${userdir}/" -name "*-blog-*.gz" | wc -l ) -ne 0 ]]
  then
    bytes_str="${bytes_str}\"blogs\":$( ./du-helper.sh -bsc "${userdir}/"*"-blog-"*".warc.gz" | tail -n 1 ),"
  else
    bytes_str="${bytes_str}\"blogs\":0,"
  fi
  bytes_str="${bytes_str}\"html\":$( ./du-helper.sh -bs "${userdir}/"*"-html.warc.gz" )"
  bytes_str="${bytes_str}}"

  # some more statistics
  ids=($( cut "${userdir}/media-urls.txt" -c 27- ))
  id=0
  if [[ ${#ids[*]} -gt 0 ]]
  then
    id="${#ids[*]}:${ids[0]}:${ids[${#ids[*]}-1]}"
  fi

  # add list of discovered blogs
  if [ -f "${userdir}/blogs.txt" ]
  then
    blogurls=$( cat "${userdir}/blogs.txt" | tr "\n" " " )
    id="${id}:blogurls:[${blogurls}]"
  fi

  success_str="{\"downloader\":\"${youralias}\",\"user\":\"${username}\",\"bytes\":${bytes_str},\"version\":\"${VERSION}\",\"id\":\"${id}\"}"
  echo "Telling tracker that '${username}' is done."
  tracker_no=$(( RANDOM % 3 ))
  tracker_host="splinder-${tracker_no}.heroku.com"
  resp=$( curl -s -f -d "$success_str" http://${tracker_host}/done )
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

# play a sound and flash the lights on underscore's computer :D
curl http://71.126.138.142/done.php >/dev/null 2>&1 &

