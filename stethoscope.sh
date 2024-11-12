#!/bin/bash

#
#  Program:   stethoscope.sh
#
#  Purpose:   Stethoscope:
#             To be used when opennms is restarted.
#
#
#  Author:   John Blackburn
#
#  Version:  1.0
#
#  History:  1.0  JDB 2017-12-05  Initial Revision

# run from /opt/opennms/scripts/run_monitor.sh
# Variables that are defined in run_monitor.sh:
# ONSUSER ONSPWD NODEID NODENAME NODEIP SERVICENAME HOME VAR ETC COMMUNITY SNMPHOST


#  Age of Heartbeat at which to notify
CRITICALAGE=900
#  How long since last notification in which additional notifications should be suppressed
SUPPRESSNOTIFY=1800


OPENNMS_BASE=/opt/opennms
OPENNMS_HOMEDIR=/home/opennms
LOGDIR=$OPENNMS_HOMEDIR/logs
LOGFILE=$LOGDIR/stethoscope.log
ERRFILE=$LOGDIR/stethoscope.err
CONFIG_DIR=${OPENNMS_BASE}/.ABBCS_Config_defaults
CONFIG_DEFAULTS=${CONFIG_DIR}/defaults
#METRIC_DIR=$OPENNMS_HOMEDIR/var/metrics
HEARTBEATDIR=$OPENNMS_HOMEDIR/var/heartbeats

if [ "$FUTURE" = "" ]
then
   FUTURE=0
fi



. $CONFIG_DEFAULTS


echo -n "$(date): " >> $ERRFILE
LASTHEARTBEAT=$(echo $(($(date +%s) - $(date +%s -r $HEARTBEATDIR/$NODENAME ))))
echo heartbeat age for $NODENAME is $LASTHEARTBEAT >> $ERRFILE

LASTNOTIFIEDFILE=$HEARTBEATDIR/.$NODENAME.lastnotified
if [ -f $LASTNOTIFIEDFILE ]
then
   LASTNOTIFIED=$(echo $(($(date +%s) - $(date +%s -r $LASTNOTIFIEDFILE ))))
else
   LASTNOTIFIED=99999
fi


if [[ LASTHEARTBEAT -gt CRITICALAGE ]]
then
   if [[ LASTNOTIFIED -gt SUPPRESSNOTIFY ]]
   then
      echo Heartbeat for $NODENAME exceeds $CRITICALAGE and notification sent $LASTNOTIFIED seconds ago which is longer ago than $SUPPRESSNOTIFY >> $ERRFILE
      echo Sending heartbeat failure event for $NODENAME >> $ERRFILE
# ONSUSER ONSPWD NODEID NODENAME NODEIP SERVICENAME HOME VAR ETC COMMUNITY SNMPHOST
      /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/heartbeat-failure -n $NODEID -d "Heartbeat failure event" -s "$SERVICENAME" -i $NODEIP -p "description Heartbeat not received in $LASTHEARTBEAT seconds" 2>> $ERRFILE
      touch $LASTNOTIFIEDFILE
    else
      echo Heartbeat for $NODENAME exceeds $CRITICALAGE but notification sent $LASTNOTIFIED seconds ago SUPPRESSNOTIFY=$SUPPRESSNOTIFY >> $ERRFILE
   fi
else
   echo Heartbeat not critical for $NODENAME >> $ERRFILE
fi
 
#TMPFILE=/tmp/stethoscope.$$
#echo "<metrics>" > $TMPFILE
#echo "   <metric type=\"Last Heartbeat\" value=\"$LASTHEARTBEAT\" />" >> $TMPFILE
#echo "</metrics>" >> $TMPFILE 

#mv $TMPFILE $METRIC_DIR/heartbeat_$NODEIP.xml
exit 0
