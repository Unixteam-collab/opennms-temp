#!/bin/bash

#
# Program Name: update_ip.sh
#
# Purpose:      To update OpenNMS with correct IP address details when an application deployment
#               changes the IP address of a node
#
# Author:       John Blackburn
#
# Description:  Due to the way application deployments can sometimes cause a node to change IP address,
#               it is necessary to update OpenNMS nodes with the changed IP address.  As it is not trivial
#               for OpenNMS to automatically detect an IP address change, this script performs that function
#
#               If /home/appliance/etc/Appliances.lst exists, this script will call check_appliance.sh for each
#               appliance listed in the file.
#
# Assumptions:  *.123 and *.124 ip addresses are always assigned to the git/services server
#
# Side Effects: Any server that this script moves into the Servers Requisition will loose its historical
#               Performance metrics
#
# Version:      1.9
#              
# History:      2017-08-03 JDB 1.0  Initial revision
#               2017-09-12 JDB 1.1  Added code to get permission to auto_update IP addresses from defaults file
#               2017-09-26 JDB 1.2  Added code to allow the DNS_AUTHORITY to be overridden
#                                   added code to attempt to use ping if DNS lookup fails
#                                   in case resolution is via hosts file
#               2017-09-28 JDB 1.3  moved gms.mincom.com domain into variable that can be overridden in defaults file
#               2017-09-29 JDB 1.4  corrected code for determining Servers current IP address
#               2017-10-05 JDB 1.5  fixed error in IP address code
#               2017-11-29 JDB 1.6  Added code to prevent deletion of IP addresses for physical appliance VM's
#               2017-12-04 JDB 1.7  Allow multiple Lookup Domains
#                                   Added call to check_appliance.sh
#               2018-02-23 JDB 1.8  Fixed IP address detection regexp
#               2018-07-10 JDB 1.9  Fixed XML decoding following change to xml format in opennms 22.0.1
#              


BASEDIR=/home/opennms
WORKDIR=$BASEDIR/FixIPs
UPDATE_LIST=$WORKDIR/iplist.dat
LOG=$BASEDIR/logs/update_IP.log
# Set default for DNS_AUTHORITY - overridden in $DEFAULTS file
DOMAIN=gms.mincom.com
DNS_AUTHORITY=10.2.0.6
CONFIG_DIR=/opt/opennms/.ABBCS_Config_defaults
DEFAULTS=${CONFIG_DIR}/defaults
APPLIANCE_LIST=${BASEDIR}/etc/Appliances.lst

. $CONFIG_DIR/.opennms.creds


Check_IP ()
{

   THIS_IP=$1
   THIS_NODE=$2


   if [[ ${THIS_NODE} =~ ^.*\.ventyxinternal ]]
   then 
      # we have an appliance vm so handle seperately
      echo ${label} is an appliance vm >> $LOG
      REAL_IP=$THIS_IP
   else
      DOMAIN_FOUND=false
      NODE=$THIS_NODE
      for DN in $DOMAIN
      do
         if [[ ${THIS_NODE} =~ ^.*\.${DN}$ ]]
         then
            #REAL_IP=$(echo $(nslookup ${THIS_NODE} $DNS_AUTHORITY | tail -2 | awk '{ print $2 }'))
            NODE=${THIS_NODE}
         else
            NSLOOKUP="$(nslookup ${THIS_NODE}.${DN} $DNS_AUTHORITY)"
            if [ $? = 0 ]
            then
               REAL_IP=$(echo $(echo "$NSLOOKUP" | tail -1 | awk '{ print $2 }'))
               NODE="${THIS_NODE}.${DN}"
               DOMAIN_FOUND=true
            fi
         fi
      done
      if [ $DOMAIN_FOUND != "true" ]
      then 
         NSLOOKUP="$(nslookup ${NODE} $DNS_AUTHORITY)"
         if [ $? = 0 ]
         then
            REAL_IP=$(echo $(echo "$NSLOOKUP" | tail -1 | awk '{ print $2 }'))
         else
            echo nslookup failed, try ping >> $LOG
            PING=$(ping -c 1 ${NODE} 2> /dev/null)
            PR=$?
            if [ $PR = 0 ]
            then
               REAL_IP=$(echo $PING | awk 'BEGIN { FS = "[()]" } { print $2 }')
            else
               REAL_IP=THIS_IP
            fi
         fi
      fi
   fi

   if [ $REAL_IP = $THIS_IP ]
   then
      #Valid IP, so check for cleanup

      # special processing for GIT servers which always have .123 and .124 addresses
      if [[ "$THIS_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.12[34]$ ]]

      then
        # got git server process accordingly
        IP1=$(echo $THIS_IP | sed 's/.$//')3 
        IP2=$(echo $THIS_IP | sed 's/.$//')4 
        IPLIST="$IP1 $IP2"
      else
        # echo normal server
        IPLIST=$THIS_IP
      fi
      for IP in $IPLIST
      do 
         grep -w $IP $WORKDIR/NoName  | while read id label
         do
            echo found $id and $label with ip $IP to delete >> $LOG
            echo deleting $id >> $LOG
            echo $id $label >> $WORKDIR/Deleters
            curl -v -H "Content-Type: application/x-www-form-urlencoded" -X DELETE http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$id >> $LOG 2>&1
         done
      done
      echo $THIS_IP
      return 0
   else
      echo $REAL_IP
      return 1
   fi
}

ReplaceIP ()
{
   CURRENT_NODE=$1
   CURRENT_IP=$2
   REAL_IP=$3

   /opt/opennms/bin/provision.pl interface add Servers $CURRENT_NODE $REAL_IP >> $LOG
   /opt/opennms/bin/provision.pl interface set Servers $CURRENT_NODE $REAL_IP snmp-primary P >> $LOG
   /opt/opennms/bin/provision.pl interface set Servers $CURRENT_NODE $CURRENT_IP snmp-primary S >> $LOG
   /opt/opennms/bin/provision.pl requisition import Servers >> $LOG
   /opt/opennms/bin/provision.pl requisition import Servers >> $LOG
   /opt/opennms/bin/provision.pl interface remove Servers $CURRENT_NODE $CURRENT_IP >> $LOG
   /opt/opennms/bin/provision.pl requisition import Servers >> $LOG
   /opt/opennms/bin/provision.pl requisition import Servers >> $LOG
}


#
# Main code starts here
#

date >> $LOG
echo Start IP check >> $LOG

# set defaults
. $DEFAULTS

# Auto IP update is something that should only be disabled in specific situations
# default to auto update if not defined in $DEFAULTS
if [ -v $UPDATE_IP ]
then
   UPDATE_IP=AUTO
fi

if [ $UPDATE_IP = "MANUAL" ]
then
  echo Automatic IP updating disabled by setting in $DEFAULTS >> $LOG
  echo UPDATE_IP=$UPDATE_IP >> $LOG
  echo ABORTING IP Update >> $LOG
  exit 1
fi

# Start with a clean slate
mkdir -p $WORKDIR
rm -f $WORKDIR/*

# Check if the "Servers" requisition exists.  If not, create it.
/opt/opennms/bin/provision.pl requisition list Servers >> $LOG 2>&1

if [ $? != 0 ]
then
   echo Creating Requisition \"Servers\" >> $LOG
   /opt/opennms/bin/provision.pl requisition add Servers >> $LOG
else
   echo Found Requisition \"Servers\" >> $LOG
fi

touch $WORKDIR/NoName

# Check nodes not in a requisition, and if a real server, move to the "Servers" Requisition
echo Checking nodes not in Requisition \"Servers\" >> $LOG

curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes?limit=0 2> /dev/null | xmllint --xpath '//nodes/node[not(@foreignSource)]/@*[name()="label" or name()="id"]' - | sed  s/label/'\nlabel'/g | (sed 1d;echo) | while read a b
do
   # decode XML
   label="${a#*\"}"
   label="${label%\"*}"
   id="${b#*\"}"
   id="${id%\"*}"
   IP_DETAILS=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$id/ipinterfaces 2> /dev/null  | xmllint --format -)
   IP_ADDR=$(echo "$IP_DETAILS" | xmllint --xpath '//ipInterfaces/ipInterface/ipAddress/text()' -)
   HOST_NAME=$(echo "$IP_DETAILS" | xmllint --xpath '//ipInterfaces/ipInterface/hostName/text()' -)
   if [[ "$label" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
   then
      REAL_IP=server
   else
      DOMAIN_FOUND=false
      NODE=$label
      for DN in $DOMAIN
      do
         if [[ ${label} =~ ^.*.${DN}$ ]]
         then
            #REAL_IP=$(echo $(nslookup ${label} $DNS_AUTHORITY | tail -2 | awk '{ print $2 }'))
            NODE=${label}
         else
            NSLOOKUP="$(nslookup ${label}.${DN} $DNS_AUTHORITY)"
            if [ $? = 0 ]
            then
               REAL_IP=$(echo $(echo "$NSLOOKUP" | tail -1 | awk '{ print $2 }'))
               NODE="${label}.${DN}"
               DOMAIN_FOUND=true
            fi
         fi
      done
      if [ $DOMAIN_FOUND != "true" ]
      then 
         NSLOOKUP="$(nslookup ${NODE} $DNS_AUTHORITY)"
         if [ $? = 0 ]
         then
            REAL_IP=$(echo $(echo "$NSLOOKUP" | tail -1 | awk '{ print $2 }'))
         else
            echo nslookup failed, try ping >> $LOG
            PING=$(ping -c 1 ${NODE} 2> /dev/null)
            PR=$?
            if [ $PR = 0 ]
            then
               REAL_IP=$(echo $PING | awk 'BEGIN { FS = "[()]" } { print $2 }')
            else
               REAL_IP=server
            fi
         fi
      fi
   fi

   echo $id:$label:$IP_ADDR:$REAL_IP >> $UPDATE_LIST

   if [ "$REAL_IP" != "server" ]
   then

      CHECK_WIN=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$id/ipinterfaces/$REAL_IP/services/MS-RDP)
      if [[ "$CHECK_WIN" == *"Monitored Service MS-RDP was not found"* ]]
      then
         REQ="Servers"
      else
         REQ="Windows_Servers"
      fi


      echo Node $label with IP $REAL_IP being moved to requisition $REQ >> $LOG
      curl -v -H "Content-Type: application/x-www-form-urlencoded" -X DELETE http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$id >> $LOG 2>&1

      /opt/opennms/bin/provision.pl node add $REQ $label $label >> $LOG
      /opt/opennms/bin/provision.pl interface add $REQ $label $REAL_IP >> $LOG
      /opt/opennms/bin/provision.pl interface set $REQ $label $REAL_IP snmp-primary P >> $LOG
   else
      echo Node $label is an IP... leave until later... >> $LOG
      echo $id $label >> $WORKDIR/NoName 
   fi
done

echo Checking Requisition \"Server\" >> $LOG

GOT_PRIMARY=false
GOT_IF=false
/opt/opennms/bin/provision.pl requisition list Servers | while read a b c d e
do
   # Decode output of provision.pl command
   if [ "$d" = "ID:" ]
   then
      CURRENT_NODE=$b
      GOT_IF=false
      GOT_PRIMARY=false
      echo Current node= $CURRENT_NODE >> $LOG
   fi
   if [ "$b" = "interfaces:" ]
   then
     GOT_IF=true
   else
     if [ "$GOT_IF" = "true" ]
     then
        CURRENT_IF=$b
        echo current IF = $CURRENT_IF >> $LOG
        GOT_IF=false
     fi
   fi
   if [ "$c" = "Primary:" ]
   then
     if [ "$d" = "P" ]
     then
        if [ $GOT_PRIMARY = "true" ]
        then
           echo already got a primary $CURRENT_IF should be Secondary >> $LOG
        else
           echo $CURRENT_IF is primary, check if valid >> $LOG
           REAL_IP=$(Check_IP $CURRENT_IF $CURRENT_NODE)
           if [ $REAL_IP = $CURRENT_IF ]
           then
             GOT_PRIMARY=true
           else
             echo got a baddy delete >> $LOG
             ReplaceIP $CURRENT_NODE $CURRENT_IF $REAL_IP
           fi
        fi
     else
        if [ $GOT_PRIMARY = "true" ]
        then
           echo got primary, $CURRENT_IF is correctly a secondary >> $LOG
        fi
        echo check if valid >> $LOG
        REAL_IP=$(Check_IP $CURRENT_IF $CURRENT_NODE)
        if [ $REAL_IP = $CURRENT_IF ]
        then
           echo got a goody do nothing >> $LOG
        else
           echo got a baddy delete >> $LOG
           ReplaceIP $CURRENT_NODE $CURRENT_IF $REAL_IP
        fi
     fi
   fi

done

/opt/opennms/bin/provision.pl requisition import Servers >> $LOG
/opt/opennms/bin/provision.pl requisition import Windows_Servers >> $LOG

date >> $LOG

if [ -f $APPLIANCE_LIST ]
then
   echo Found Ellipse Appliances being monitored Checking IP addresses
   for APPLIANCE in $(cat $APPLIANCE_LIST)
   do
      echo Checking $APPLIANCE >> $LOG
      /opt/opennms/scripts/check_appliance.sh $APPLIANCE >> $LOG
      date >> $LOG
   done
fi


echo Finish IP check >> $LOG


