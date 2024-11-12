#!/bin/bash

#
# Program Name:  check_appliance.sh
#
# Purpose:       To extract the list of VM's from an appliance and Add/Update node in OpenNMS
#                If VM doesn't exist in OpenNMS, then add it
#                If IP address of VM has changed then update record in OpenNMS
#
# Prerequisites: must be able to run /home/opennms/get_vmlist.sh on appliance
#                mk_appliance_snmp_config.sh must have been run on appliance host to set up snmp.
#
# Version:       2.3
#
# History:       1.0 2017-11-25 JDB Initial revision
#                2.0 2017-12-12 JDB Re-written to use OpenNMS tools for updating OpenNMS config rather
#                                   than directly modifying XML files
#                2.1 2018-07-10 JDB Modified xml attribute extration to use xpath option of xmllint
#                2.2 2018-10-24 JDB fixed xmllint parameters
#                2.3 2019-03-11 JDB Add physical appliance node to "Appliance" category
#

APPLIANCE=$1

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

LOGFILE=/home/opennms/logs/check_appliance.log

if [ $# != 1 ]
then
  echo ERROR: Missing appliance name
  echo Usage:  $0 appliance
  exit 1
fi

echo $(date) Start scan $APPLIANCE  >> $LOGFILE

#APPLIANCE_IP=$(nslookup $APPLIANCE | tail -2 | grep Address | awk '{ print $2}')
APPLIANCE_IP=$(/opt/opennms/scripts/getNodeIP.sh $APPLIANCE)
REQUISITION=Appliance
GET_NODES=/opt/opennms/scripts/get_appliance_nodes.sh


# Check if the "Appliance" requisition exists.  If not, create it.
/opt/opennms/bin/provision.pl requisition list Appliance 2>&1 > /dev/null

if [ $? != 0 ]
then
   echo Creating Requisition \"Appliance\" | tee -a $LOGFILE
   /opt/opennms/bin/provision.pl requisition add Appliance
else
   echo Found Requisition \"Appliance\" | tee -a $LOGFILE
fi

#Ensure physical appliance is in the "Appliance" category
/opt/opennms/bin/provision.pl category add Servers $APPLIANCE Appliance
sleep 1
/opt/opennms/bin/provision.pl requisition import Servers


$GET_NODES $APPLIANCE_IP | while read GUEST IP
do
   APPL=$(echo $APPLIANCE | awk -F. '{print $1}'| awk -F"-s-" '{ print $1$2}')

   CMTY=$(echo $GUEST | awk -F . '{print "cmty_"$1$2"'$APPL'"}')
   RF_NAME=$(echo $GUEST | awk -F . '{print $1 "." $2 ".'$APPLIANCE'" }')

   NODEINFO="$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$REQUISITION:$RF_NAME 2> /dev/null)"

   #CURRENT_CMTY=$(provision.pl snmp get $IP | grep community | awk -F'(: )' '{ print $2}')
   if [ "$NODEINFO" = "Node $REQUISITION:$RF_NAME was not found." ]
   then
       echo $GUEST not found, need to add | tee -a $LOGFILE
       /opt/opennms/bin/provision.pl snmp set $IP $CMTY proxy-host=$APPLIANCE_IP
       sleep 1
       /opt/opennms/bin/provision.pl node add $REQUISITION $RF_NAME $RF_NAME
       /opt/opennms/bin/provision.pl interface add $REQUISITION $RF_NAME $IP
       /opt/opennms/bin/provision.pl interface set $REQUISITION $RF_NAME $IP snmp-primary P
   else
       echo $GUEST found, need to check | tee -a $LOGFILE
       IP_ADDR=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$REQUISITION:$RF_NAME/ipinterfaces 2> /dev/null  | xmllint --xpath '//ipInterfaces/ipInterface[contains(@snmpPrimary,"P")]/ipAddress/text()' -)
       
       echo Old IP = $IP_ADDR New IP = $IP | tee -a $LOGFILE

       if [ "$IP" != "$IP_ADDR" ]
       then
          /opt/opennms/bin/provision.pl snmp set $IP_ADDR public
          sleep 1
          /opt/opennms/bin/provision.pl snmp set $IP $CMTY proxy-host=$APPLIANCE_IP
          sleep 1
          /opt/opennms/bin/provision.pl interface add $REQUISITION $RF_NAME $IP
          /opt/opennms/bin/provision.pl interface set $REQUISITION $RF_NAME $IP snmp-primary P
          /opt/opennms/bin/provision.pl interface set $REQUISITION $RF_NAME $IP_ADDR snmp-primary S
          sleep 1
          /opt/opennms/bin/provision.pl requisition import $REQUISITION
          sleep 1
          /opt/opennms/bin/provision.pl requisition import $REQUISITION
          sleep 1
          /opt/opennms/bin/provision.pl interface remove $REQUISITION $RF_NAME $IP_ADDR
          sleep 1
          /opt/opennms/bin/provision.pl requisition import $REQUISITION
          sleep 1
          /opt/opennms/bin/provision.pl requisition import $REQUISITION
       else
          echo Old IP = New IP.  Not changing | tee -a $LOGFILE
       fi
   fi
done


sleep 1
/opt/opennms/bin/provision.pl requisition import $REQUISITION 

echo
echo Please allow 5 minutes for OpenNMS to process changes


echo $(date) End scan $APPLIANCE >> $LOGFILE
