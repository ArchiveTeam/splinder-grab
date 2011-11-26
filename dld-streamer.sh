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
# Usage:   dld-streamer.sh ${YOURALIAS} ${MAX_THREADS} [usernamefile]
#
# If usernamefile is provided, it will get a list of usernames from
# the named file, rather than the tracker. This is useful for things
# like retrying users that errored before.
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
max_jobs="$2"
itemfile="$3"

if [[ ! $youralias =~ ^[-A-Za-z0-9_]+$ ]]
then
  echo "Usage:  $0 {nickname} {count}"
  echo "Run with a nickname with only A-Z, a-z, 0-9, - and _"
  echo "Count is maximum number of child processes to run."
  exit 4
fi

if [[ -n "$itemfile" && ! -r "$itemfile" ]]
then
  echo "item list file \"$itemfile\" does not exist or is"
  echo "not readable."
  exit 4
fi

outputline()
{
  dt=`date --rfc-3339=seconds`
  echo "[$dt] $*"
}

outputstartline()
{
  dt=`date --rfc-3339=seconds`
  echo -n "[$dt] $*"
}

outputendline()
{
  echo "$*"
}

initial_stop_mtime='0'
if [ -f STOP ]
then
  initial_stop_mtime=$( stat -c '%Y' STOP )
fi

# open the file, if specified
if [[ -n "$itemfile" ]]
then
  exec 4< "$itemfile"
fi

declare -A pids_users

fork_more=1

mkdir -p ./logs

while true
do
  if [[ ${#pids_users[*]} -eq $max_jobs || $fork_more -eq 0 ]]
  then
    sleep 1
  fi
  count="${#pids_users[*]}/$max_jobs "

  if [[ $fork_more -eq 1 ]] && [[ -f STOP && $( stat -c '%Y' STOP ) -gt $initial_stop_mtime ]]
  then
    outputline "$count Stopping on request..."
    fork_more=0
  fi

  if [[ $( jobs -p -r | wc -l ) -lt $max_jobs && $fork_more -eq 1 ]]
  then
    if [[ -z "$itemfile" ]]
    then
      # request a username
      outputstartline "$count Getting next username from tracker..."
      tracker_no=$(( RANDOM % 3 ))
      tracker_host="splinder-${tracker_no}.heroku.com"
      username=$( curl -s -f -d "{\"downloader\":\"${youralias}\"}" http://${tracker_host}/request )

      # empty?
      if [ -z $username ]
      then
        echo
        outputline "Tracker uncooperative.  Pausing for 30 seconds..."
        echo
        sleep 30
      fi
    else
      outputstartline "$count Reading next username from list..."
      # read until we get a non-empty line or end-of-file
      username=
      while [[ -z "$username" && $fork_more -eq 1 ]]
      do
        read -u 4 username
        if [[ $? -ne 0 ]]
        then
          outputendline " end of list reached."
          fork_more=0
        fi
     done
    fi

    # not empty?
    if [ -n $username ]
    then
      outputendline " downloading ${username}"
      echo $username >> downloads.log

      ./dld-single.sh "$youralias" "$username" > "./logs/${username}.log" &
      pids_users["$!"]="$username"
    fi
  fi

  # reap dead children
  # all done!
  if [[ ${#pids_users[*]} -eq 0 ]]
  then
    wait
    exit
  fi

  # This is kind of stupid but it is a decent workaround for bash's
  # lack of being able to wait on a single process (unless I'm stupid
  # and missed something).  I keep a hash of started job pids (the
  # keys in pids_users) and check it against currently running jobs
  # (the values in pids_jobs).
  pids_jobs=(`jobs -p -r`)
  for job in ${!pids_users[*]}
  do
    found=0
    for pid in ${pids_jobs[*]}
    do
      if [[ $pid -eq $job ]] ; then
        found=1
      fi
    done
    if [[ $found -eq 0 ]] ; then
      fin_usr=${pids_users[$job]}
      # child has died, not found in running jobs list
      outputstartline "$count PID $job finished '$fin_usr': "
      wait $job
      status=$?
      if [[ $status -ne 0 ]] ; then
        outputendline "Error - exited with status $status."
        echo "$fin_usr" >> error-usernames
      else
        outputendline "Success."
        rm "./logs/${fin_usr}.log"
      fi

      # remove this child from the jobs list
      unset pids_users[$job]
    fi
  done
done

