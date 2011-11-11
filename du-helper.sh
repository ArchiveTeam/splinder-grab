#!/bin/bash
#
# Checks if the `du' in $PATH supports --apparent-size.
#
# If it doesn't, one common cause is that the `du' in $PATH isn't GNU du.  On
# such systems, GNU du is sometimes aliased to gdu, so try that instead.  If
# nothing works, use a messier-but-workable default.

userdir=$2
opts=$1

if ( du --help 2>&1 | grep -q apparent-size )
then
  du --apparent-size $opts "$userdir" | cut -f 1
elif ( which -s gdu )
then
  gdu --apparent-size $opts "$userdir" | cut -f 1
else
  du -hs "$userdir" | cut -f 1
fi
