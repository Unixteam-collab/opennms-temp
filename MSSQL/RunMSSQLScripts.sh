#!/bin/bash

OPENNMS_HOME=/home/opennms
CONFIG=$OPENNMS_HOME/etc
LOGS=$OPENNMS_HOME/logs
BIN=/opt/opennms/scripts/MSSQL

# 
#
if [ $# != 1 ]
then
   echo "Usage: $0 [MSSQL|4HMSSQL|DMSQL|WMSSQL]"
   echo "   MSSQL run every 10 minutes"
   echo "   4HMSSQL run every 4 hours"
   echo "   DMSSQL run once a day at 2:30am"
   echo "   WMSSQL run once a week at 3:30am on Sunday"
   exit 1
fi

PREFIX=$1

PATH=/bin:/usr/bin:/opt/opennms/bin:$BIN
export PATH

CFG_COUNT=$(ls -1 $CONFIG/${PREFIX}* 2> /dev/null | wc -l )

if [ $(id -u) -eq 0 ]
then
   echo  Error:  $0 cannot be run as root user
   exit 1
fi

if [ $CFG_COUNT -ge 1  ]
then
  for FILE in $(ls $CONFIG/${PREFIX}*)
  do
     SCRIPT=$(basename $FILE)
     LOGFILE=$LOGS/$SCRIPT.log
     (
        flock -xn 200 || exit 1
        $CONFIG/$SCRIPT >> $LOGFILE 2>&1
     ) 200> $OPENNMS_HOME/var/${SCRIPT}.lock &
  done
else
   echo nothing to do...
fi

