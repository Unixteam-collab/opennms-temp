#!/bin/bash

#
# Program Name: eventcapture.sh
#
# Purpose: to capture an event/notification from OpenNMS and convert it into an event file
#          in the incoming directory for later processing
#
# Version: 1.21
#
# History: 17-02-2017  1.1  JDB  Added process number to params file to prevent multiple concurrent
#                                calls from clashing (re-entrant)
#          20-02-2017  1.2  JDB  Added code to detect "RESOLVED" events and process differently
#                               (Current action does nothing for resolved events - resolved event processing
#                                to be added at a later date)
#          21-02-2017  1.3  JDB	 Added code to record categories passed to script and their translated value.
#	   27-03-2017  1.4  JDB  Added Category translation for DBA, Windows, and Asset Suite
#	   26-07-2017  1.5  JDB  Modified event filename to use message key rather than eventid.  To assist
#                                with deduplication of events with sane message ID.
#	   31-07-2017  1.6  JDB  Added double quotes around variables to prevent characters within parameter values
#                                from incorectly being interpreted by the shell.
#	   21-08-2017  1.7  JDB  strip linefeed from $MESSAGE
#	   11-09-2017  1.8  JDB  Added Category translation for ABBCS_EllipseHttp
#                                Fixed Log file generation for concurrent executions (re-entrant)
#          09-03-2018  1.9  JDB  Fixed code that detects "RESOLVED" events
#                                Added category translation for Windows services
#          31-10-2018  1.10 JDB  Sanitize RESOURCEID
#          14-06-2019  1.11 JDB  Added OGMESSAGEKEY so that Opsgenie can have a different MESSAGEKEY to Remedy Force
#                                Required to make better use of OpsGenie Event correlation features.
#                                Removed code that blocks resolved tickets so these can get passed to OpsGenie.
#                                Resolved ticket blocking code moved to submit_ticket.pl for RF submission.   
#          19-07-2019  1.12 JDB  Added code to cater for FSMon
#          06-08-2019  1.13 JDB  Modified FSMon processing to inject the threshold value into the MESSAGE
#	   15-10-2019  1.14 JDB  Added Category translation for ABBCS_Ellipse9Http
#	   23-10-2019  1.15 JDB  Added Categories for Data Protector
#	   07-04-2020  1.16 JDB  Added VMware severities
#	   24-04-2020  1.17 JDB  Sanitize STDIN from OpenNMS call.  (remove nested single quotes)
#	   29-04-2020  1.18 JDB  Added cleanup of tmp file genertated in 1.17
#	   06-05-2020  1.19 JDB  Fixed Windows Server filesystem alert message constructor
#          14-05-2020  1.20 JDB  Due to issues with excess single quotes being added to MESSAGE by OpenNMS in some cases
#                                Initial extraction of STDIN passed parameters now handled by extract_params.sh script
#          12-08-2020  1.21 JDB  Ignore comment lines from FSMon Conf file
#          27-08-2020  1.22 AK   Added AXIS in category parameters.
#

PATH=/usr/bin
export PATH

PARMFILE=/opt/rfinteg/var/eventcapture_parms.$$
PARMFILE_TMP="${PARMFILE}.tmp"
LOGFILE=/opt/rfinteg/var/eventcapture.log
TEMPLOG=/opt/rfinteg/var/eventcapture.log.$$
RFINTEG_INCOMING_DIR=/opt/rfinteg/var/incoming
CATEGORIES=/opt/rfinteg/var/categories.list

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds


date >> $TEMPLOG
echo ==== environment === >> $TEMPLOG
env >> $TEMPLOG

echo ==== parameters === >> $TEMPLOG

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

# Sanitize parameters passed via STDIN
echo ==== STDIN === >> $TEMPLOG
#cat - | tee -a $TEMPLOG | strings > $PARMFILE
cat - | tee -a $TEMPLOG | /opt/opennms/scripts/extract_params.sh $PARMFILE
echo  >> $TEMPLOG

## Sanitize PARMFILE - now done via extract_params.sh script
## the following code is to ensure only 1st and last single quote characters in a line remain.
## this is to resolve the issue with OpenNMS adding single quoted string so that we end up with nested quotes
## this code 
#mv $PARMFILE $PARMFILE_TMP
#cat $PARMFILE_TMP | while read str
#do
#  count=$(echo "$str" | sed -E 's/(.)/\1\n/g' | grep -c -o \')
#  if [ $count -gt 2 ]
#  then
#    beg=$(echo "$str" | cut -d \' -f1)
#    rest=$(echo "$str" | cut -d \' -f2-)
#    mid=$(echo $rest | sed "s/\(.*\)'.*/\1/"| sed s/\'//g)
#    end=$(echo "$str" | echo "${str##*\'}")
#    final=$beg\'$mid\'$end
#  else
#    final="$str"
#  fi
#  echo "$final"
#done > $PARMFILE
chmod +x $PARMFILE

echo ==== SANITIZED PARMFILE === >> $TEMPLOG
cat $PARMFILE >> $TEMPLOG

. $PARMFILE

echo ==== extracted parameters === >> $TEMPLOG

echo PARAM_DESTINATION = "$PARAM_DESTINATION" >> $TEMPLOG
echo PARAM_NUM_MSG = "$PARAM_NUM_MSG" >> $TEMPLOG
echo PARAM_RESPONSE = "$PARAM_RESPONSE" >> $TEMPLOG
echo PARAM_NODE = "$PARAM_NODE" >> $TEMPLOG
echo PARAM_INTERFACE = "$PARAM_INTERFACE" >> $TEMPLOG
echo PARAM_SERVICE = "$PARAM_SERVICE" >> $TEMPLOG
echo PARAM_SUBJECT = "$PARAM_SUBJECT" >> $TEMPLOG
echo PARAM_EMAIL = "$PARAM_EMAIL" >> $TEMPLOG
echo PARAM_TUI_PIN = "$PARAM_TUI_PIN" >> $TEMPLOG
echo RESOURCEID = "$RESOURCEID" >> $TEMPLOG
echo NODE = "$NODE"  >> $TEMPLOG
echo LABEL = "$LABEL" >> $TEMPLOG
echo NOTICEID = "$NOTICEID"  >> $TEMPLOG
echo SEVERITY = "$SEVERITY"  >> $TEMPLOG
echo SERVICE = "$SERVICE"  >> $TEMPLOG
echo EVENTID = "$EVENTID"  >> $TEMPLOG
echo OPERATORINSTRUCT = "$OPERATORINSTRUCT"  >> $TEMPLOG
echo MESSAGE = "$MESSAGE"  >> $TEMPLOG
echo passed CATEGORY = "$CATEGORY" >> $TEMPLOG

 
echo >> $TEMPLOG
echo Sanitzing RESOURCEID >> $TEMPLOG
RESOURCEID="$(echo -e "$RESOURCEID" |  tr -d '[:space:]/#')"

echo Sanitized RESOURCEID = "$RESOURCEID" >> $TEMPLOG

echo >> $TEMPLOG
 

# Get Subscription ID if it exists
SUB_ID=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$PARAM_NODE/assetRecord | xmllint --xpath "string(//department)" - )
RG=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$PARAM_NODE/assetRecord | xmllint --xpath "string(//division)" - )
OSTYPE=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$PARAM_NODE/categories/Microsoft | xmllint --xpath "string(//category/@name)" - 2>/dev/null)

echo Subscription = $SUB_ID >> $TEMPLOG
echo Resource Group = $RG >> $TEMPLOG
echo OSTYPE = $OSTYPE >> $TEMPLOG
echo >> $TEMPLOG

# Extract Business Impact for node for use by Opsgenie ticket submission to alter priority
ENVTYPE=$(/opt/opennms/scripts/getEnvType.sh $PARAM_NODE)

echo Category lookup for $CATEGORY >> $TEMPLOG
RAW_CATEGORY="$CATEGORY"

case "${CATEGORY}" in
   ns-dskPercent) CATEGORY="Operating System"
       ;;
   ORACLE|Oracle|Database) CATEGORY="Database"
       ;;
   MST|NTFS|Window|Windows|WIN*) CATEGORY="Window"
       ;;
   COMMS|Network|Networks) CATEGORY="Network"
       ;;
   "Asset Suite") CATEGORY="Asset Suite"
       ;;
   "ABBCS-EllipseHttp"|"ABBCS-Ellipse9Http"|"Ellipse") CATEGORY="Ellipse"
       ;;
   "AXIS") CATEGORY="AXIS"
       ;;
   "OpenNMS-Postgres") CATEGORY="DropEvent"
       ;;
   *)
       if [ "$OSTYPE" == "Microsoft" ]
       then
          CATEGORY=Window
       else
          CATEGORY="Operating System"
       fi
       ;;
esac

CATEGORY="$(/opt/opennms/scripts/getCategories.sh $PARAM_NODE "$CATEGORY")"

# FSMon Processing
if [ "$SERVICE" = 'ABBCS-FSMon' ]
then
   echo FSMon Alert  - Customising MESSAGE and CATEGORY >> $TEMPLOG
   DATFILE=/home/opennms/var/metrics/FSMon/$NODE.dat
   CONFFILE=/home/opennms/etc/FSMon/$NODE.conf
   
   # Due to backslashes in MS drive letters, some escape character gymnastics was required to ensure the data for 
   # Microsoft disks is correctly found.  Without this 1st modification of $LABEL, the proceeding uses of $LABEL were
   # providing an incorrect number of '/' characters to the grep command.
   LABEL="$(echo "${LABEL}" | sed -e 's/\\/\\\\/g')"

   # read values that triggered this alert
   read ID IP_ADDR SERVER SIZE USED PCT_USED NOTIFY FS  <<< $(grep " $(echo "${LABEL}" | sed -e 's/\\/\\\\/g')\$" $DATFILE)
   
   echo DATFILE $DATFILE content is: >> $TEMPLOG
   cat $DATFILE >> $TEMPLOG
   echo CONFFILE $CONFFILE content is: >> $TEMPLOG
   cat $CONFFILE >> $TEMPLOG
   # extract threshold values to enable insertion of triggering threshold into MESSAGE
   read P4 P3 P2 P1 N1 F1  <<< $(grep -v "^#" $CONFFILE | grep " $(echo "${LABEL}" | sed -e 's/\\/\\\\/g')\$" )
   case $SEVERITY
      in
      Warning)
         THRESHOLD="${P4}%"
         ;;
      Minor|Yellow)
         THRESHOLD="${P3}%"
         ;;
      Major)
         THRESHOLD="${P2}%"
         ;;
      Critical|Red)
         THRESHOLD="${P1}%"
         ;;
      *)
         THRESHOLD="(Undef - Check Config)"
         ;;
   esac
   echo THRESHOLD for SEVERITY of $SEVERITY is $THRESHOLD >> $TEMPLOG

   MESSAGE="Filesystem $LABEL on $SERVER has reached $PCT_USED% which is over the $SEVERITY threshold of ${THRESHOLD} for this filesystem.\nThis threshold can be modified in $HOSTNAME:$CONFFILE"
   echo MESSAGE updated to: $MESSAGE >> $TEMPLOG
   case "$NOTIFY" in
        UNIX)
          CATEGORY="Operating System"
          ;;
        MST)
          CATEGORY="Window"
          ;;
        APPS)
          CATEGORY="Ellipse"
          ;;
        DBA)
          CATEGORY="Database"
          ;; 
       AXIS)
          CATEGORY="AXIS"
          ;;
        COMMS)
          CATEGORY="Network"
          ;;
        *)
          CATEGORY="Operating System"
   esac
    
   echo CATEGORY reset for FSMon to: $CATEGORY >> $TEMPLOG

fi
# End FSMon processing

echo Category now = "$CATEGORY"  >> $TEMPLOG

echo $RAW_CATEGORY "$CATEGORY" >> $CATEGORIES

# Check if this is a "RESOLVED" notification

if [[ "$PARAM_NUM_MSG" =~ RESOLVED.* ]]
then
   # Extract $NODE from PARMFILE as OpenNMS adds "RESOLVED: " to the 1st line causing a failure to set the NODE variable.
   eval $(head -1 $PARMFILE| awk '{ print $2 }')
   echo Event is a resolved event for $NODE >> $TEMPLOG

   ## Resolved Notification processing to go here...
   NODE=$(/opt/opennms/scripts/getNodeName.sh $PARAM_NODE)
   MESSAGE="RESOLVED: $MESSAGE"
   SEVERITY=cleared
   echo "Forced Severity to cleared for Resolved event" >> $TEMPLOG
fi

  if [ "X$RESOURCEID" == "X" ]
  then
     RESOURCEID="${EVENTID}:${NOTICEID}"
  fi

  echo ==== RF Integration Data === >> $TEMPLOG
  EVENT="${HOSTNAME}:${NODE}:${EVENTID}:${NOTICEID}"
  RFMESSAGEKEY="${HOSTNAME}:${NODE}:${SEVERITY}:${RESOURCEID}"
  OGMESSAGEKEY="${HOSTNAME}:${NODE}:${RESOURCEID}"
  EVENT_FILE="${RFINTEG_INCOMING_DIR}/${RFMESSAGEKEY}"

  echo "$NODE" > "${EVENT_FILE}"
  echo "${SEVERITY,,}" >> "${EVENT_FILE}"
  echo "$EVENT" >> "${EVENT_FILE}"
  # convert linefeeds to preserve
  echo "$MESSAGE" | sed ':a;N;$!ba;s/\n/\\n/g' >> "${EVENT_FILE}"
  echo "$CATEGORY" >> "${EVENT_FILE}"
  echo "$RFMESSAGEKEY" >> "${EVENT_FILE}"
  echo "$OGMESSAGEKEY" >> "${EVENT_FILE}"
  echo "$SUB_ID" >> "${EVENT_FILE}"
  echo "$RG" >> "${EVENT_FILE}"
  echo "$ENVTYPE" >> ${EVENT_FILE}

  cat "${EVENT_FILE}" >> $TEMPLOG



echo  >> $TEMPLOG
echo ====================== >> $TEMPLOG
echo  >> $TEMPLOG

cat $TEMPLOG >> $LOGFILE
rm -f $PARMFILE $TEMPLOG $PARMFILE_TMP
# temporary added to cleanup previous sloppy code that left it there...
find /opt/rfinteg/var/ -name \*.tmp -mtime +1 -exec rm {} \;
exit 0
