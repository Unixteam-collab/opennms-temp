#!/bin/bash

BASE=/opt/SyncKit
CONFIG_DIR=$BASE/etc
BIN=$BASE/bin
SYNC_STATS_DIR=$BASE/var
LOG_DIR=$BASE/log

export CONFIG_DIR
export SYNC_STATS_DIR
export LOG_DIR

if [ ! -d $CONFIG_DIR ]
then
  mkdir -p $CONFIG_DIR
fi

if [ ! -d $SYNC_STATS_DIR ]
then
  mkdir -p $SYNC_STATS_DIR
fi

if [ ! -d $LOG_DIR ]
then
  mkdir -p $LOG_DIR
fi

for SYNC in `ls -1 $CONFIG_DIR`
do
   LOG="${LOG_DIR}/${SYNC}.log"
   export LOG
   export SYNC

   # set default threshold (seconds)
   THRESHOLD=1200
   export THRESHOLD

   date >> $LOG

   /usr/bin/flock -xn /dev/shm/sync_${SYNC}.lck -c '(

      . $CONFIG_DIR/$SYNC >> $LOG 2>&1

      if [ $? = 0 ]
      then
        echo Success at $(date) >> $LOG
        echo MESSAGE=\"$MESSAGE\" > $SYNC_STATS_DIR/$SYNC
        echo THRESHOLD=$THRESHOLD >> $SYNC_STATS_DIR/$SYNC
        echo -n TS= >> $SYNC_STATS_DIR/$SYNC
        date "+%s" >> $SYNC_STATS_DIR/$SYNC
      else
        echo Failed at $(date) >> $LOG
      fi
   )'  #end flock command

   if [ $? != 0 ]
   then 
      echo sync $SYNC already running >> $LOG
   fi
   
   
done
