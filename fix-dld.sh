#!/bin/bash
#
# Fix script errors in early downloads.
#
# This script will look in your data/ directory for downloads and
# fix the following (if necessary):
#
#  * Redo any US download that has 502 or 504 erorrs.
#
# Note: this script will NOT fix any user that's still being
# downloaded, that is, anything that has an .incomplete file.
# This means that you can run this script while a normal
# client is downloading, but you can't use this script to fix
# interrupted downloads.
#
# Usage:   fix-dld.sh ${YOURALIAS}
#

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

for d_country in data/*
do
  country=$( basename "$d_country" )
  find $d_country -mindepth 4 -maxdepth 4 -type d | while read d
  do
    username=$( basename "$d" )
    need_fix=0

    if [ -f "${d}/.incomplete" ]
    then
      echo "${country}:${username} is still incomplete, not fixing."
      continue
    fi

    # FIX 1: check for 50? errors
    if [[ $country = us ]]
    then
      if grep -q "ERROR 50" "${d}/wget"*".log"
      then
        echo "${country}:${username} contains 502 or 504 errors, needs to be fixed."
        touch "${d}/.incomplete"
        need_fix=1
      fi
    fi

    # fix, if necessary
    if [[ $need_fix -eq 1 ]]
    then
      if ! ./dld-single.sh "$youralias" "${country}:${username}"
      then
        exit 6
      fi
    fi

    if [ -f STOP ] && [[ $( stat -c '%Y' STOP ) -gt $initial_stop_mtime ]]
    then
      exit
    fi
  done
done

