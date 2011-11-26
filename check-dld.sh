#!/bin/bash
#
# Check your downloads.
#
# This script will look in your data/ directory for downloads and
# tell you which users are incomplete and/or need to be fixed.
# It will not actually fix anything.
#
# Usage:   check-dld.sh
#
# Incomplete users will be output to stderr, and users with errors
# will be output to stdout. You can use it to generate a list suitable
# for dld-streamer.sh by doing this:
#
# ./check-dld.sh | cut -d " " -f 1
#
# where the character in the quotes is a space.

for d_country in data/*
do
  country=$( basename "$d_country" )
  find $d_country -mindepth 4 -maxdepth 4 -type d | while read d
  do
    username=$( basename "$d" )

    # check for any incomplete downloads
    if [ -f "${d}/.incomplete" ]
    then
      echo "${country}:${username} is still incomplete." >&2
      continue
    fi

    # FIX 1: check for 50? errors
    if [[ $country = us ]]
    then
      if grep -q "ERROR 50" "${d}/wget"*".log"
      then
        echo "${country}:${username} contains 502 or 504 errors, needs to be fixed."
        continue
      fi
    fi

    # FIX 2: check for splinder_noconn.html
    if grep -q "splinder_noconn.html" "${d}/wget"*".log"
    then
      echo "${country}:${username} contains maintenance pages, needs to be fixed."
      continue
    fi
  done
done

