#!/bin/bash

#
# Program Name: heartbeatcapture.sh
#
# Purpose: to assist recording heartbeat events from remote opennms servers
#          in the incoming directory for later processing
#
# Version: 1.3
#
# History: 12-02-2020  1.0  JDB  Initial revision
#          26-02-2020  1.1  JDB  improve outage processing so that a new outage that
#                                arrives while an existing outage is in place will
#                                reset the outage as if it has just started.
#                                Added locking so that an outage being added doesn't
#                                get cancelled by the regular heartbeat call.
#          18-03-2020  1.2  JDB  Modified for event to use autoaction rather than using a notification
#          21-07-2020  1.3  JDB  set notifyCategory of monitored node to that reported by the monitored node
#

PATH=/usr/bin
export PATH

LOGFILE=/home/opennms/logs/heartbeatcapture.log
TEMPLOG=/home/opennms/var/heartbeatcapture.log.$$
HEARTBEAT_STORE=/home/opennms/var/heartbeats

NODE=$1
OUTAGE=$2
NOTIF_CATEGORY=$3
REQ=$($WORK/opt/opennms/scripts/getNodeReq.sh $NODE)


function fileAge
{
    local fileMod
    if fileMod=$(stat -c %Y -- "$1")
    then
        echo $(( $(date +%s) - $fileMod ))
    else
        return $?
    fi
}

if [ ! -d $HEARTBEAT_STORE ]
then
   mkdir -p $HEARTBEAT_STORE
fi


date >> $TEMPLOG
echo ==== environment === >> $TEMPLOG
env >> $TEMPLOG

echo ==== parameters === >> $TEMPLOG


if [ "X$OUTAGE" == "X" ]
then 
   OUTAGE=0
fi

echo NODE=$NODE >> $TEMPLOG
echo Outage Length = $OUTAGE >> $TEMPLOG
echo Notify Category = $NOTIF_CATEGORY >> $TEMPLOG
 
echo >> $TEMPLOG

UPDATES=$($WORK/opt/opennms/scripts/set_asset.sh $REQ $NODE notifyCategory "$NOTIF_CATEGORY")

if [ "$UPDATES" = "true" ]
then
  /opt/opennms/bin/provision.pl requisition import $REQ
  sleep 10
  /opt/opennms/bin/provision.pl requisition import $REQ
fi


LOCKFILE=$HEARTBEAT_STORE/.hb_${NODE}.lock
(
   flock -x -w 10 200 ||  exit 1

   if [ -f $HEARTBEAT_STORE/$NODE ]
   then
      HB_AGE=$(( 0 - ( $(fileAge $HEARTBEAT_STORE/$NODE) / 60 ) ))
   else
      HB_AGE=-99999
   fi

   echo Minutes until outage expiry: $HB_AGE >> $TEMPLOG

   if [ $HB_AGE \< $OUTAGE ]
   then
      echo Outage Expiry less than $OUTAGE minutes, poking timestamp to set outage for $OUTAGE minutes >> $TEMPLOG
      touch -t $(date -d "$OUTAGE min" "+%Y%m%d%H%M") $HEARTBEAT_STORE/$NODE
   else
      echo Outage Expiry greater than $OUTAGE minutes.  Leave it alone >> $TEMPLOG
   fi
) 200> $LOCKFILE


cat $TEMPLOG >> $LOGFILE
rm $TEMPLOG
exit 0

