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
# Assumptions:  *.123 and *.124 ip addresses are always assigned to the git/services server
#
# Side Effects: Any server that this script moves into the Servers Requisition will loose its historical
#               Performance metrics
#
# Version:      1.4
#              
# History:      2017-08-03 JDB 1.0  Initial revision
#               2017-09-12 JDB 1.1  Added code to get permission to auto_update IP addresses from defaults file
#               2017-09-26 JDB 1.2  Added code to allow the DNS_AUTHORITY to be overridden
#                                   added code to attempt to use ping if DNS lookup fails
#                                   in case resolution is via hosts file
#               2017-09-28 JDB 1.3  moved gms.mincom.com domain into variable that can be overridden in defaults file
#               2017-09-29 JDB 1.4  corrected code for determining Servers current IP address
#              


BASEDIR=/home/opennms
WORKDIR=$BASEDIR/FixIPs
UPDATE_LIST=$WORKDIR/iplist.dat
LOG=$BASEDIR/logs/update_IP.log
LOG=/dev/tty
# Set default for DNS_AUTHORITY - overridden in $DEFAULTS file
DOMAIN=gms.mincom.com
DNS_AUTHORITY=10.2.0.6
DEFAULTS=/opt/opennms/.ABBCS_Config_defaults/defaults

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds



Check_IP ()
{

   THIS_IP=$1
   THIS_NODE=$2


   #then
   #   REAL_IP=$(echo $(nslookup ${THIS_NODE} $DNS_AUTHORITY | tail -2 | awk '{ print $2 }'))
   #else
   #   REAL_IP=$(echo $(nslookup ${THIS_NODE}.${DOMAIN} $DNS_AUTHORITY | tail -2 | awk '{ print $2 }'))
   #fi

   if [[ ${THIS_NODE} =~ ^.*.${DOMAIN}$ ]]
   then
      #REAL_IP=$(echo $(nslookup ${THIS_NODE} $DNS_AUTHORITY | tail -2 | awk '{ print $2 }'))
      NODE=${label}
   else
      #REAL_IP=$(echo $(nslookup ${THIS_NODE}.${DOMAIN} $DNS_AUTHORITY | tail -2 | awk '{ print $2 }'))
      NODE=${THIS_NODE}.${DOMAIN}
   fi
   NSLOOKUP=$(nslookup ${NODE} $DNS_AUTHORITY)
   if [ $? = 0 ]
   then
      REAL_IP=$(echo $(echo "$NSLOOKUP" | tail -2 | awk '{ print $2 }'))
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

   if [ $REAL_IP = $THIS_IP ]
   then
      #Valid IP, so check for cleanup

      # special processing for GIT servers which always have .123 and .124 addresses
      if [[ "$THIS_IP" =~ ^[0-9]*.[0-9]*.[0-9]*.12[34]$ ]]
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
echo            curl -v -H "Content-Type: application/x-www-form-urlencoded" -X DELETE http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$id >> $LOG 2>&1
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

echo   /opt/opennms/bin/provision.pl interface add Servers $CURRENT_NODE $REAL_IP >> $LOG
echo   /opt/opennms/bin/provision.pl interface set Servers $CURRENT_NODE $REAL_IP snmp-primary P >> $LOG
echo   /opt/opennms/bin/provision.pl interface set Servers $CURRENT_NODE $CURRENT_IP snmp-primary S >> $LOG
echo   /opt/opennms/bin/provision.pl requisition import Servers >> $LOG
echo   /opt/opennms/bin/provision.pl requisition import Servers >> $LOG
echo   /opt/opennms/bin/provision.pl interface remove Servers $CURRENT_NODE $CURRENT_IP >> $LOG
echo   /opt/opennms/bin/provision.pl requisition import Servers >> $LOG
echo   /opt/opennms/bin/provision.pl requisition import Servers >> $LOG
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
curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes?limit=0 2> /dev/null | xmllint --format - | grep "node label" | while read a b c d
do
   # decode XML
   label="${b#*\"}"
   label="${label%\"*}"
   id="${c#*\"}"
   id="${id%\"*}"
   IP_DETAILS=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$id/ipinterfaces 2> /dev/null  | xmllint --format -)
   IP_ADDR=$(echo "$IP_DETAILS" | grep ipAddress)
   IP_ADDR="${IP_ADDR#*\>}"
   IP_ADDR="${IP_ADDR%%\<*}"
   HOST_NAME=$(echo "$IP_DETAILS" | grep hostName)
   HOST_NAME="${HOST_NAME#*\>}"
   HOST_NAME="${HOST_NAME%%\<*}"
   if [[ "$label" =~ ^[0-9]*.[0-9]*.[0-9]*.[0-9]$ ]]
   then
      REAL_IP=server
   else
      if [[ ${label} =~ ^.*.${DOMAIN}$ ]]
      then
         #REAL_IP=$(echo $(nslookup ${label} $DNS_AUTHORITY | tail -2 | awk '{ print $2 }'))
         NODE=${label}
      else
         #REAL_IP=$(echo $(nslookup ${label}.${DOMAIN} $DNS_AUTHORITY | tail -2 | awk '{ print $2 }'))
         NODE=${label}.${DOMAIN}
      fi
      NSLOOKUP=$(nslookup ${NODE} $DNS_AUTHORITY)
      if [ $? = 0 ]
      then
         REAL_IP=$(echo $(echo "$NSLOOKUP" | tail -2 | awk '{ print $2 }'))
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

   echo $id:$label:$IP_ADDR:$REAL_IP >> $UPDATE_LIST

   if [ "$REAL_IP" != "server" ]
   then
      echo Node $label with IP $REAL_IP being moved to requisition Server >> $LOG
echo      curl -v -H "Content-Type: application/x-www-form-urlencoded" -X DELETE http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$id >> $LOG 2>&1
echo      /opt/opennms/bin/provision.pl node add Servers $label $label >> $LOG
echo      /opt/opennms/bin/provision.pl interface add Servers $label $REAL_IP >> $LOG
echo      /opt/opennms/bin/provision.pl interface set Servers $label $REAL_IP snmp-primary P >> $LOG
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

date >> $LOG
echo Finish IP check >> $LOG

