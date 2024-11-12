#!/bin/bash

OPENNMS_HOME=/home/opennms
CONFIG=$OPENNMS_HOME/etc
LOGS=$OPENNMS_HOME/logs
BIN=/opt/opennms/scripts/EllipseBatch
PREFIX=Ellipse

ORACLE_HOME=`find /oracle/product/ -maxdepth 1|grep 12.|sort|tail -1`
export ORACLE_HOME

PATH=$ORACLE_HOME/bin:/bin:/usr/bin:/opt/opennms/bin:$BIN
export PATH

CFG_COUNT=$(ls -1 $CONFIG/${PREFIX}* 2> /dev/null | wc -l )

LD_LIBRARY_PATH=$(dirname $(find /oracle -name libclntsh.so | grep 12. 2> /dev/null))
export LD_LIBRARY_PATH

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
        date >> $LOGFILE
        $CONFIG/$SCRIPT >> $LOGFILE 2>&1
     ) 200> $OPENNMS_HOME/var/${SCRIPT}.lock &
  done
else
   echo nothing to do...
fi

