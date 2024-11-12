#!/bin/bash

SOURCE=$1


NUMBER_TO_KEEP=30
FAILED=false
CURDTE=$(date +%Y%m%d%H%M)

#rsync -avz --delete -e "ssh -oBatchMode=yes" abc-evap01-svc-git01:/etc/cups/ /etc/cups

rsync -vrulpEogtb --suffix=.$CURDTE --rsync-path=/bin/rsync "$SOURCE":/etc/cups/cupsd.conf /etc/cups/cupsd.conf
if [ $? != 0 ]
then
   echo Failed to sync cupsd.conf
   FAILED=true
else
    ls -d1tr /etc/cups/cupsd.conf.* | head -n -$NUMBER_TO_KEEP | xargs -d '\n' rm -f
fi

rsync -vrulpEogtb --suffix=.$CURDTE --rsync-path=/bin/rsync "$SOURCE":/etc/cups/printers.conf /etc/cups/printers.conf
if [ $? != 0 ]
then
   echo Failed to sync printers.conf
   FAILED=true
else
    ls -d1tr /etc/cups/printers.conf.* | head -n -$NUMBER_TO_KEEP | xargs -d '\n' rm -f
fi

rsync -vrulpEogtb --suffix=.$CURDTE --rsync-path=/bin/rsync "$SOURCE":/etc/cups/ppd/ /etc/cups/ppd
if [ $? != 0 ]
then
   echo Failed to sync ppd files
   FAILED=true
else
   for PPD in /etc/cups/ppd/*.ppd 
   do
      ls -d1tr $PPD.* 2> /dev/null | head -n -$NUMBER_TO_KEEP | xargs -d '\n' rm -f
   done

fi


if [ $FAILED = 'true' ]
then
   exit 1
else
   exit 0
fi

