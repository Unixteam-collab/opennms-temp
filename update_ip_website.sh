#!/bin/bash

#
# Program Name: update_ip_website.sh
#
# Purpose:      To maintain OpenNMS ip address assignment for External Websites where
#               we have no control over the IP address.
#
# Author:       John Blackburn
#
# Description:  When monitoring exteral URL's we cannot control the IP address, so this script checks DNS and updates
#               OpenNMS if required
#
# Version:      1.0
#              
# History:      2019-04-03 JDB 1.0  Initial revision
#              


BASEDIR=/home/opennms
LOG=$BASEDIR/logs/update_IP_Website.log
# Set default for DNS_AUTHORITY - overridden in $DEFAULTS file
#DOMAIN=gms.mincom.com
#DNS_AUTHORITY=10.2.0.6
DEFAULTS=/opt/opennms/.ABBCS_Config_defaults/defaults

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds



Check_IP ()
{

   THIS_IP="$1"
   THIS_NODE=$2

   if [ $(grep -v "^#" /etc/hosts | grep -c $THIS_NODE) = 0 ]
   then
      NSLOOKUP="$(nslookup ${THIS_NODE})"
      REAL_IP=$(echo $(echo "$NSLOOKUP" | tail -1 | awk '{ print $2 }'))
   else
     REAL_IP=$(grep -v "^#" /etc/hosts | grep $THIS_NODE | cut -d\   -f1 | head -1)
   fi

   if [ $REAL_IP = "$THIS_IP" ]
   then
      #Valid IP, so check for cleanup

      echo "$THIS_IP"
      return 0
   else
      echo $REAL_IP
      return 1
   fi
}

ReplaceIP ()
{
   CURRENT_NODE=$1
   CURRENT_IP="$2"
   REAL_IP=$3

   /opt/opennms/bin/provision.pl interface add WebSite $CURRENT_NODE $REAL_IP  >> $LOG
   /opt/opennms/bin/provision.pl interface set WebSite $CURRENT_NODE $REAL_IP snmp-primary P  >> $LOG
   if [ "$CURRENT_IP"X != "X" ]
   then
      /opt/opennms/bin/provision.pl interface set WebSite $CURRENT_NODE $CURRENT_IP snmp-primary S  >> $LOG
   fi
   /opt/opennms/bin/provision.pl requisition import WebSite  >> $LOG
   /opt/opennms/bin/provision.pl requisition import WebSite  >> $LOG
   if [ "$CURRENT_IP"X != "X" ]
   then
      /opt/opennms/bin/provision.pl interface remove WebSite $CURRENT_NODE $CURRENT_IP  >> $LOG
      /opt/opennms/bin/provision.pl requisition import WebSite  >> $LOG
      /opt/opennms/bin/provision.pl requisition import WebSite  >> $LOG
   fi
}


#
# Main code starts here
#

date >> $LOG
echo Start IP check >> $LOG

# Check if the "WebSite" requisition exists.  If not, create it.
/opt/opennms/bin/provision.pl requisition list WebSite >> $LOG 2>&1

if [ $? != 0 ]
then
   echo Creating Requisition \"WebSite\" >> $LOG
   /opt/opennms/bin/provision.pl requisition add WebSite >> $LOG
else
   echo Found Requisition \"WebSite\" >> $LOG
fi

echo Checking Requisition \"WebSite\" >> $LOG


for SITETAG in $(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions/WebSite 2> /dev/null| sed -e "s/xmlns/ignore/" | xmllint --xpath '//model-import/node/@foreign-id' -)
do
   SITE=$(echo "$SITETAG" | cut -d\" -f 2)
   CUR_IP=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions/WebSite/nodes/$SITE 2> /dev/null | sed -e "s/xmlns/ignore/" | xmllint --xpath '//node/interface/@ip-addr'  - 2> /dev/null| cut -d\" -f 2)

   if [ "X$CUR_IP" = X ]
   then
       echo no interface defined, no services defined to carry over>> $LOG
       SERVICES=""
   else
       SERVICES=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions/WebSite/nodes/$SITE/interfaces/$CUR_IP/services 2> /dev/null | sed -e "s/xmlns/ignore/" | xmllint --xpath '//services/monitored-service/@service-name' - 2> /dev/null)
   fi
   echo check if valid >> $LOG
   REAL_IP=$(Check_IP "$CUR_IP" $SITE)

   echo REAL is $REAL_IP >> $LOG
   if [ $REAL_IP = "$CUR_IP" ]
   then
      echo IP is current. Nothing to do >> $LOG
   else
      if [ $REAL_IP = '255.255.255.255' ]
      then
         echo website not currently up.  >> $LOG
      else
         echo IP has changed, updating >> $LOG
         ReplaceIP $SITE "$CUR_IP" $REAL_IP 
         for SERVICETAG in $SERVICES
         do
            SERVICE=$(echo $SERVICETAG | cut -d\" -f 2)
            /opt/opennms/bin/provision.pl service add WebSite $SITE $REAL_IP $SERVICE >> $LOG
         done
         /opt/opennms/bin/provision.pl requisition import WebSite >> $LOG
         /opt/opennms/bin/provision.pl requisition import WebSite >> $LOG
      fi
   fi
done


date >> $LOG

echo Finish IP check >> $LOG


