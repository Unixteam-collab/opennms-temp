#!/bin/bash

#PATH=/usr/bin
#export PATH


PARMFILE=/tmp/_parms.resolved
RFINTEG_INCOMING_DIR=/opt/rfinteg/var/incoming
LOGFILE=/opt/rfinteg/var/rfinteg.resolved
date >> $LOGFILE
echo ==== environment === >> $LOGFILE
env >> $LOGFILE

echo ==== parameters === >> $LOGFILE

PARM=""
VAL=""
eval $(while [ $# -gt 0 ]
do
   PARM=$1
   shift
   if [[ "$1" == *PARAM* ]]
   then 
      VAL=""
   else
      VAL=$1
      shift
   fi
   echo "$PARM\"$VAL\""
done)

echo ==== STDIN === >> $LOGFILE
cat - | strings> $PARMFILE
cat $PARMFILE >> $LOGFILE
chmod +x $PARMFILE
echo  >> $LOGFILE
. $PARMFILE

echo ==== extracted parameters === >> $LOGFILE

echo PARAM_DESTINATION = $PARAM_DESTINATION >> $LOGFILE
echo PARAM_NUM_MSG = $PARAM_NUM_MSG >> $LOGFILE
echo PARAM_RESPONSE = $PARAM_RESPONSE >> $LOGFILE
echo PARAM_NODE = $PARAM_NODE >> $LOGFILE
echo PARAM_INTERFACE = $PARAM_INTERFACE >> $LOGFILE
echo PARAM_SERVICE = $PARAM_SERVICE >> $LOGFILE
echo PARAM_SUBJECT = $PARAM_SUBJECT >> $LOGFILE
echo PARAM_EMAIL = $PARAM_EMAIL >> $LOGFILE
echo PARAM_TUI_PIN = $PARAM_TUI_PIN >> $LOGFILE
echo CATEGORY = $CATEGORY >> $LOGFILE
echo RESOURCEID = $RESOURCEID >> $LOGFILE
echo NODE = $NODE  >> $LOGFILE
echo NOTICEID = $NOTICEID  >> $LOGFILE
echo SEVERITY = $SEVERITY  >> $LOGFILE
echo SERVICE = $SERVICE  >> $LOGFILE
echo EVENTID = $EVENTID  >> $LOGFILE
echo OPERATORINSTRUCT = $OPERATORINSTRUCT  >> $LOGFILE
echo MESSAGE = $MESSAGE  >> $LOGFILE

echo >> $LOGFILE

if [ "X$RESOURCEID" == "X" ]
then
   RESOURCEID=${EVENTID}:${NOTICEID}
fi

echo ==== RF Integration Data === >> $LOGFILE
EVENT="${HOSTNAME}:${NODE}:${EVENTID}:${NOTICEID}"
MESSAGEKEY="${HOSTNAME}:${NODE}:${SEVERITY}:${RESOURCEID}"

echo EVENT = $EVENT >> $LOGFILE
echo MESSAGEKEY = $MESSAGEKEY >> $LOGFILE

#EVENT_FILE="${RFINTEG_INCOMING_DIR}/${EVENT}"

#echo $NODE > $EVENT_FILE
#echo ${SEVERITY,,} >> $EVENT_FILE
#echo $EVENT >> $EVENT_FILE
#echo $MESSAGE >> $EVENT_FILE
##echo GMS-UNIX-ADMIN >> $EVENT_FILE
#echo $CATEGORY >> $EVENT_FILE
#echo $MESSAGEKEY >> $EVENT_FILE

#cat $EVENT_FILE >> $LOGFILE


echo  >> $LOGFILE
echo ====================== >> $LOGFILE
echo  >> $LOGFILE
exit 0

