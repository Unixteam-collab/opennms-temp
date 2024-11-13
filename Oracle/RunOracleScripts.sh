#!/bin/bash

CONFIG=/home/opennms/etc
LOGS=/home/opennms/logs
BIN=/opt/opennms/scripts/Oracle

# 
#
if [ $# != 1 ]
then
   #echo "Usage: $0 [MSSQL|4HMSSQL|WMSSQL]"
   echo "Usage: $0 [Oracle|1HROracle]"
   echo "   Oracle: run every 10 minutes"
# other prefix schedules will need to be setup in cron
   exit 1
fi

PREFIX=$1

#PREFIX=Oracle

PATH=/bin:/usr/bin:/opt/opennms/bin
export PATH

CFG_COUNT=$(ls -1 $CONFIG/${PREFIX}* 2> /dev/null | wc -l )

LD_LIBRARY_PATH=$(dirname $(find /oracle -name libclntsh.so 2> /dev/null))
export LD_LIBRARY_PATH

if [ $(id -u) -eq 0 ]
then
   echo  Error:  $0 cannot be run as root user
   exit 1
fi


if [ $CFG_COUNT -ge 1  ]
then
  for CFG in $(ls $CONFIG/${PREFIX}*)
  do
     LOGFILE=$LOGS/$(basename $CFG).log
     cat $CFG | while read CMD
        do
              SCRIPT=$(echo $CMD | awk '{ print $1 }')
              if [ -f "$BIN/$SCRIPT" ]
              then
		if [ `echo $CMD | awk '{ print $5 }' | grep -i magasdw` ] && (( `date +%H` < 6 || `date +%H` > 16 )) 
		then
		      	echo "Skipping" `echo $CMD | awk '{ print $5 }'` ": Daily DW refresh outage window"
	        else
                $BIN/$CMD >> $LOGFILE 2>&1
		fi
              fi
        done
  done
else
   echo nothing to do...
fi

