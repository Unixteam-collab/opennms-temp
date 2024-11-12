##############################################################################
##
##  Oracle_EIP.sh - Oracle DB EIP OpenNMS Monitoring 
##
##  Author: Maurice Reardon, MAR-2020
##
##  Brief:  Installed on OpenNMS collector :-
##
##    This script checks for volumes of EIP records over alert threshold 
##
##  Parameters:
##             $1 = OpenNMS node (hostname_DBname)
##             $2 = Target DB user
##             $3 = Target DB pass
##             $4 = ORACLE_SID of DB being monitored
##
##  eg.
##    Oracle_EIP.sh server_DB device_ID abbmon pass DB
##
##
##  Dependencies:-
##
##  The following oracle crontab jobs need to run on the DB server:
##
## Snowy EIP Hourly monitoring data collection
## 0 * * * * /oracle/scripts/eip/hourly.ksh snhelpr2
## Snowy EIP Daily monitoring data collection
## 01 12 * * * /oracle/scripts/eip/daily.ksh snhelpr2
##
##
##############################################################################

# -- Start Functions

Check_shell_cmd ()  {

# Normally this script will be run through cron with the full path name
# If it is run manually ensure the full path is used and a SID is passed

   if [ "$SCRIPT" = "Oracle_EIP.sh" ] || [ "$SCRIPT" = "./Oracle_EIP.sh" ] ; then
      echo "Exiting, Use full pathname when running this script!"
      return 1
   fi
   if [ "$ORACLE_SID" = "" ] ; then
      echo "Exiting, no instance passed!"
      return 1
   else
      export ORACLE_SID
   fi
}

Main () {

   HERE=`dirname $SCRIPT` ;  INSTALLDIR=`dirname $HERE`

   Set_environment        # Set Parameters and Oracle environment variables
   if [ "$?" != "0" ] ; then
      Finish_up
   fi

   Run_query

   Finish_up

}

Set_environment ()  {

   ORACLE_HOME=`find /oracle/product/ -maxdepth 1|grep 12.|sort|tail -1`
   PATH=$PATH:$ORACLE_HOME/bin
   export ORACLE_HOME PATH

}

Run_query ()  {

   # Query the database and raise alerts if any over threshold 

EVENT_STAGING=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
set heading off trimspool on serverout on feedback off
select count from abbmon.rowcount where table_name='EVENT_STAGING' and time=(select max(time) from abbmon.rowcount where table_name='EVENT_STAGING');
exit
EOF`
if [ $EVENT_STAGING -gt 1000 ]; then
  string="EIP EVENT_STAGING undelivered threshold=1000, currently $EVENT_STAGING"
  message=$(echo $string)
  /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/EIP-trigger -n $TARGETDEVICEID -d "Ellipse EIP" -p "value $EVENT_STAGING" -p "description $message" -p "resourceId EVENT_STAGING"
fi

ACTIVEMQ_MSGS_ellipseservices=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
set heading off trimspool on serverout on feedback off
select count from abbmon.rowcount where table_name='ACTIVEMQ_MSGS_ellipseservices' and time=(select max(time) from abbmon.rowcount where table_name='ACTIVEMQ_MSGS_ellipseservices');
exit
EOF`
if [ $ACTIVEMQ_MSGS_ellipseservices -gt 12000 ]; then
  string="EIP ACTIVEMQ_MSGS_ellipseservices threshold=12000, currently $ACTIVEMQ_MSGS_ellipseservices"
  message=$(echo $string)
  /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/EIP-trigger -n $TARGETDEVICEID -d "Ellipse EIP" -p "value $ACTIVEMQ_MSGS_ellipseservices" -p "description $message" -p "resourceId ACTIVEMQ_MSGS_ellipseservices"
fi

ACTIVEMQ_MSGS_mib_event_reply=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
set heading off trimspool on serverout on feedback off
select count from abbmon.rowcount where table_name='ACTIVEMQ_MSGS_mib.event.reply' and time=(select max(time) from abbmon.rowcount where table_name='ACTIVEMQ_MSGS_mib.event.reply');
exit
EOF`
if [ $ACTIVEMQ_MSGS_mib_event_reply -gt 5000 ]; then
  string="EIP ACTIVEMQ_MSGS_mib_event_reply threshold=5000, currently $ACTIVEMQ_MSGS_mib_event_reply"
  message=$(echo $string) 
  /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/EIP-trigger -n $TARGETDEVICEID -d "Ellipse EIP" -p "value $ACTIVEMQ_MSGS_mib_event_reply" -p "description $message" -p "resourceId ACTIVEMQ_MSGS_mib_event_reply"
fi

ACTIVEMQ_MSGS_mib_event_reply_MuleP=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
set heading off trimspool on serverout on feedback off
select count from abbmon.rowcount where table_name='ACTIVEMQ_MSGS_mib.event.reply_MuleP' and time=(select max(time) from abbmon.rowcount where table_name='ACTIVEMQ_MSGS_mib.event.reply_MuleP');
exit
EOF`
if [ $ACTIVEMQ_MSGS_mib_event_reply_MuleP -gt 10 ]; then
  string="EIP ACTIVEMQ_MSGS_mib_event_reply_MuleP threshold=10, currently $ACTIVEMQ_MSGS_mib_event_reply_MuleP"
  message=$(echo $string)
  /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/EIP-trigger -n $TARGETDEVICEID -d "Ellipse EIP" -p "value $ACTIVEMQ_MSGS_mib_event_reply_MuleP" -p "description $message" -p "resourceId ACTIVEMQ_MSGS_mib_event_reply_MuleP"
fi

ACTIVEMQ_ACKS_diff=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
set heading off trimspool on serverout on feedback off
select count from abbmon.rowcount where table_name='ACTIVEMQ_ACKS_diff' and time=(select max(time) from abbmon.rowcount where table_name='ACTIVEMQ_ACKS_diff');
exit
EOF`
if [ $ACTIVEMQ_ACKS_diff -gt 100000 ]; then
  string="EIP ACTIVEMQ_ACKS_diff threshold=100000, currently $ACTIVEMQ_ACKS_diff"
  message=$(echo $string)
  /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/EIP-trigger -n $TARGETDEVICEID -d "Ellipse EIP" -p "value $ACTIVEMQ_ACKS_diff" -p "description $message" -p "resourceId ACTIVEMQ_ACKS_diff"
fi

ACTIVEMQ_ACKS_invalid_subs=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
set heading off trimspool on serverout on feedback off
select trim(sub_name) from ellipse.activemq_acks where sub_name not in
('APMCClientSubscriberEQPROD',
'APMCClientSubscriberWOPROD',
'APMCClientSubscriberWRPROD',
'EquipmentEventRoute',
'WorkOrderEventRoute',
'WorkRequestEventRoute',
'MuleP',
'CanonicalDefectUpdate',
'CanonicalDefectAttachmentUpdate',
'CanonicalDefectTypeAlarmUpdate',
'DEIMTranslateAttachments',
'CanonicalInspectionResultIngest',
'CanonicalDefectTypeUpdate',
'InspectionScript',
'CanonicalWorkOrderTaskUpdate',
'CanonicalAssetHistoryUpdate',
'ARTCWorkOrder',
'ARTCWorkOrderStandardText',
'ARTCWorkOrderTask');
exit
EOF`
if [ ${#ACTIVEMQ_ACKS_invalid_subs} -gt 0 ]; then
  ACTIVEMQ_ACKS_invalid_subs_count=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
  set heading off trimspool on serverout on feedback off
  select trim(to_char(count(*))) from ellipse.activemq_acks where sub_name not in
  ('APMCClientSubscriberEQPROD',
  'APMCClientSubscriberWOPROD',
  'APMCClientSubscriberWRPROD',
  'EquipmentEventRoute',
  'WorkOrderEventRoute',
  'WorkRequestEventRoute',
  'MuleP',
  'CanonicalDefectUpdate',
  'CanonicalDefectAttachmentUpdate',
  'CanonicalDefectTypeAlarmUpdate',
  'DEIMTranslateAttachments',
  'CanonicalInspectionResultIngest',
  'CanonicalDefectTypeUpdate',
  'InspectionScript',
  'CanonicalWorkOrderTaskUpdate',
  'CanonicalAssetHistoryUpdate',
  'ARTCWorkOrder',
  'ARTCWorkOrderStandardText',
  'ARTCWorkOrderTask');
  exit
  EOF`
  string="EIP $ACTIVEMQ_ACKS_invalid_subs_count Invalid Subs found=$ACTIVEMQ_ACKS_invalid_subs"
  message=$(echo $string)
  /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/EIP-trigger -n $TARGETDEVICEID -d "Ellipse EIP ACTIVEMQ_ACKS - Invalid Subs found," -p "description $message" -p "resourceId ACTIVEMQ_ACKS_invalid_subs"
fi

#ESB_MESSAGE=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
#set heading off trimspool on serverout on feedback off
#select count from abbmon.rowcount where table_name='ESB_MESSAGE' and time=(select max(time) from abbmon.rowcount where table_name='ESB_MESSAGE');
#exit
#EOF`
#if [ $ESB_MESSAGE -gt 100000 ]; then
#  string="EIP ESB_MESSAGE threshold=100000, currently $ESB_MESSAGE"
#  message=$(echo $string)
#  /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/EIP-trigger -n $TARGETDEVICEID -d "Ellipse EIP" -p "value $ESB_MESSAGE" -p "description $message" -p "resourceId ESB_MESSAGE"
#fi

}


Finish_up ()  {
   exit
}

# --- End functions ---

SCRIPT=$0
OPENNMS_NODE=$1         # Full OpenNMS Node name for the monitored DB
TARGETDEVICEID=$(/opt/opennms/scripts/getNodeID.sh $OPENNMS_NODE)
USER=$2                 # DB user to connect to monitored DB
PASS=$3                 # DB pass to connect to monitored DB
ORACLE_SID=$4          # Oracle SID of monitored DB

Check_shell_cmd        # Validate script command used and SID passed
if [ "$?" != "0" ]
then
   exit
fi

Main

