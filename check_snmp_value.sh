#!/bin/ksh

# check_snmp_value.sh node community oid threshold sev category "Message"
#
# for Ellipse batch failure checking, add the following to /home/opennms/etc/Ellipse_check_batch_fail
#/opt/opennms/scripts/check_snmp_value.sh ellbat0-prd-p03-kum kum-evap01 .1.3.6.1.4.1.2021.16.2.1.5.1 1 critical Ellipse "Batch Hung Error: NotificationPollingService - Unable to read/process new notification requests."




NODE=$1
COMMUNITY=$2
OID=$3
THRESHOLD=$4
SEV=$5
CATEGORY=$6
MESSAGE="$7"

# SEV is one of:
#minor
#warn
#major
#critical


UEI="uei.opennms.org/ABBCS/SNMP-$SEV"
VAR=/home/opennms/var
LASTFILE="${VAR}/check_snmp${OID}.prev"

if [ -f "$LASTFILE" ]
then
   LASTVAL=$(cat $LASTFILE)
   if ! [[ "$LASTVAL" =~ ^[0-9]+$ ]]
   then
      LASTVAL=0
   fi
else
   LASTVAL=0
fi

NODE_ID=$(/opt/opennms/scripts/getNodeID.sh $NODE)
if [ $? != 0 ]
then
   echo Unable to determine OpenNMS NodeID for $NODE
   exit 1
fi
NODE_IP=$(/opt/opennms/scripts/getNodeIP.sh $NODE)
if [ $? != 0 ]
then
   echo Unable to determine IP address for $NODE
   exit 1
fi


CURRVAL=$(snmpget -v2c -c $COMMUNITY $NODE_IP $OID | awk '{ print $NF}')
TYPE=$(snmpget -v2c -c $COMMUNITY $NODE_IP $OID | awk '{ print $(NF-1) }')

echo $CURRVAL > $LASTFILE

if [[ $TYPE == "Counter"* ]]
then
   VALUE=$(( $CURRVAL - $LASTVAL ))
else
   VALUE=$CURRVAL
fi
if [ $VALUE -ge $THRESHOLD ]
then
   send-event.pl $UEI -n $NODE_ID -d "SNMP Threshold" -p "label SNMP" -p "resourceId $OID" -p "ds $CATEGORY" -p "description $MESSAGE current count $VALUE threshold $THRESHOLD" 
else
   echo ok
fi
