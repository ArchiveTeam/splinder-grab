#!/bin/bash
#
# Distributed downloading script for Splinder.com.
#
# This will get a username from the tracker and download data
# from www.splinder.com or www.us.splinder.com.
#
# You need wget-warc to run this script. Please compile it and
# copy the wget executable as wget-warc to the same directory
# as these scripts.
#
# Usage:   dld-client.sh ${YOURALIAS}
#
# To stop the script gracefully,  touch STOP  in the script's
# working directory. The script will then finish the current
# user and stop.
#

# this script needs wget-warc, which you can find on the ArchiveTeam wiki.
# copy the wget executable to this script's working directory and rename
# it to wget-warc

if [ ! -x ./wget-warc ]
then
  echo "wget-warc not found. Download and compile wget-warc and save the"
  echo "executable as ./wget-warc"
  exit 3
fi

# things are downloaded into here and then removed after the warc is
# completed.
if [ ! -d ./tmpfs ]
then
  echo "You really should mount a tmpfs on ./tmpfs , like so (run as root):"
  echo "mount -t tmpfs -o size=1200M tmpfs ./tmpfs"
  mkdir ./tmpfs
fi

# the script also needs curl

if ! builtin type -p curl &>/dev/null
then
  echo "You don't have curl."
  exit 3
fi

youralias="$1"

if [[ ! $youralias =~ ^[-A-Za-z0-9_]+$ ]]
then
  echo "Usage:  $0 {nickname}"
  echo "Run with a nickname with only A-Z, a-z, 0-9, - and _"
  exit 4
fi

initial_stop_mtime='0'
if [ -f STOP ]
then
  initial_stop_mtime=$( stat -c '%Y' STOP )
fi

while [ ! -f STOP ] || [[ $( stat -c '%Y' STOP ) -le $initial_stop_mtime ]]
do
  # request a username
  echo -n "Getting next username from tracker..."
  tracker_no=$(( RANDOM % 3 ))
  tracker_host="splinder-${tracker_no}.heroku.com"
  username=$( curl -s -f -d "{\"downloader\":\"${youralias}\"}" http://${tracker_host}/request )

  # empty?
  if [ -z $username ]
  then
    echo
    echo "No username. Sleeping for 30 seconds..."
    echo
    sleep 30
  else
    echo " done."

    if ! ./dld-single.sh "$youralias" "$username"
    then
      echo "Error downloading '$username'."
      exit 6
    fi
  fi
done

