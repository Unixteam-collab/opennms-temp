#!/bin/bash

# Script to post warning notication when send-event.pl script changes.
#
#  This script has been distributed to the following non-opennms locations and needs to be updated when send-event.pl changes
#

NOTICE="
WARNING === WARNING === WARNING
WARNING === WARNING === WARNING
WARNING === WARNING === WARNING

send-event.pl has changed and must be distributed in synchronisation to
    this update

#   AXIS --- AXIS team will need to distribute new send-event.pl script
#   ELK  --- send-event.pl is used by ELK to send messages to opennms
#   Dataprotector notifications
 
WARNING === WARNING === WARNING
WARNING === WARNING === WARNING
WARNING === WARNING === WARNING
WARNING === WARNING === WARNING
"
#
#
#   If send-event.pl is distributed to other places, it should be added to this script so that this script can prompt 
#   appropriate redistribution.

SCRIPT_LOCATION=/opt/opennms/bin/send-event.pl
SCRIPT_CKSUM=/home/opennms/var/SENDEVENT.CKSUM


if [ -f $SCRIPT_CKSUM ]
then
   ORIG_CKSUM=$(cat $SCRIPT_CKSUM)
else
   ORIG_CKSUM=notset
fi

CURRENT_CKSUM=$(cksum $SCRIPT_LOCATION)

if [ "$CURRENT_CKSUM" != "$ORIG_CKSUM" ]
then
   echo "$NOTICE"
   echo $CURRENT_CKSUM > $SCRIPT_CKSUM
else
   echo send-event.pl is unchanged
fi

