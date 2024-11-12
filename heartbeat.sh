#!/bin/bash

#
#  Program:   heartbeat.sh
#
#  Purpose:   To generate monitoring heartbeat.  Passing parameter of minutes will
#             set a length of time a lack of heartbeat is ok - effectively a planned outage
#
#  Parameters:
#        Minutes - Number of minutes to add to the heartbeat timestamp to allow for an outage
#
#  Author:   John Blackburn
#
#  Version:  1.4
#
#  History:  1.0  JDB 2020-02-20  Initial Revision
#            1.1  JDB 2020-03-02  added timeouts and error checking to CURL calls
#            1.2  JDB 2020-05-11  stop sending heartbeat to localhost as this isn't checked anyway
#                                 and is only confusing support staff when they check if heartbeat is working.
#            1.3  JDB 2020-06-12  Ensure heartbeat services are correctly created
#            1.4  JDB 2020-07-21  send notifyCategory to monitoring server so that this server is monitored
#                                 with the correct priority




OPENNMS_BASE=/opt/opennms
OPENNMS_HOMEDIR=/home/opennms
LOGDIR=$OPENNMS_HOMEDIR/logs
LOGFILE=$LOGDIR/heartbeat.log
ERRFILE=$LOGDIR/heartbeat.err
CONFIG_DIR=${OPENNMS_BASE}/.ABBCS_Config_defaults
CONFIG_DEFAULTS=${CONFIG_DIR}/defaults
FUTURE=$1


# $WORK is only defined in install_customisations.sh when installing updates
NOTIF_CAT=$($WORK/opt/opennms/scripts/get_notifyCategory.sh $(hostname))

if [ "$FUTURE" = "" ]
then
   FUTURE=0
fi

check_service ()
{
   FS=$1
   ONS_HOST=$2
   NODE_NAME=$3
   NODE_ID=$4
   SERVICE=$5


   NODE_IP_XML=$(curl -k -m 15 http://$ONSUSER:$ONSPWD@$ONS_HOST:8980/opennms/rest/nodes/$NODE_ID/ipinterfaces\?limit=0 2> /dev/null )
   if [ $? != 0 ]
   then
      echo CURL failed getting node id
      exit
   fi

   NODE_IP=$(echo "$NODE_IP_XML" | xmllint --xpath '//ipInterfaces/ipInterface[contains(@snmpPrimary,"P")]/ipAddress/text()' -)

   RES=$(curl -k -m 15 -s http://$ONSUSER:$ONSPWD@${ONS_HOST}:8980/opennms/rest/nodes/$NODE_ID/ipinterfaces/$NODE_IP/services/$SERVICE)
   if [ $? != 0 ]
   then
      echo CURL failure getting service
      exit
   fi

   if [[ "$RES" = "Monitored Service $SERVICE was not found"* ]]
   then
      /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest service add $FS $NODE_NAME $NODE_IP $SERVICE
      /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest requisition import $FS
   fi
}


check_remote_ons ()
{
   ONS_HOST=$1

   FS="OpenNMSServers"
   HOST=$(hostname)
   FSID="$FS:$HOST"
   MY_IP=$(hostname -I | head -1 | cut -d\  -f1)
   echo checking Remote Monitor $ONS_HOST for presence of $FSID with an IP of $MY_IP 

   # Check if the "$FS" requisition exists.  If not, create it.
   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest requisition list $FS

   if [ $? != 0 ]
   then
      echo Creating Requisition \"$FS\ on $ONS_HOST"
      /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest requisition add $FS
   else
      echo Found Requisition \"$FS\ on $ONS_HOST"
   fi


   #if [ ! -v SNMP_COMMUNITY ]
   #then
   #  /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest snmp set $IP_ADDR $SNMP_COMMUNITY
   #fi

   echo Creating $HOST in $FS on $ONS_HOST with $MY_IP
   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest node add $FS $HOST $HOST
   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest interface add $FS $HOST $MY_IP
   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest interface set $FS $HOST $MY_IP snmp-primary P

   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest requisition import $FS

}


get_node_id()
{


  ONS_HOST=$1
  THIS_HOST=$(hostname)
  echo Looking for node id of $THIS_HOST on $ONS_HOST >> $ERRFILE

  for REQ in Servers OpenNMSServers
  do
     echo Checking Requisition $REQ >> $ERRFILE
     for DOM in "" $(for i in $DOMAIN; do echo ".$i"; done)
     do
        echo Checking Domain \"$DOM\" >> $ERRFILE
        # get ONS Node ID for automatic outage
        MON_HOST=${THIS_HOST}${DOM}
        echo MON_HOST evalutates to $MON_HOST >> $ERRFILE
        echo curl -k -m 15 -s http://$ONSUSER:ONSPWD@${ONS_HOST}:8980/opennms/rest/nodes/$REQ:${MON_HOST} >> $ERRFILE
        ONS_NODE_ID_XML=$(curl -k -m 15 -s http://$ONSUSER:$ONSPWD@${ONS_HOST}:8980/opennms/rest/nodes/$REQ:${MON_HOST} 2>/dev/null) 2>/dev/null
        if [ $? != 0 ]
        then
           echo CURL FAILURE getting node id >> $ERRFILE
           exit
        fi
        ONS_NODE_ID=$(echo $ONS_NODE_ID_XML |  xmllint --xpath '//node/@id' - 2>/dev/null| awk -F \" '{ print $2 }') 2>/dev/null

        if [ "${ONS_NODE_ID}X" != "X" ]
        then
           echo Found Node ID $ONS_NODE_ID in DOM Loop >> $ERRFILE
           break
        fi
     done
     if [ "${ONS_NODE_ID}X" != "X" ]
     then
        echo Found Node ID $ONS_NODE_ID in REQ Loop >> $ERRFILE
        break
     fi
  done


  if [ "${ONS_NODE_ID}X" = "X" ]
  then 
     # For new server, there will not yet be a node in opennms.  If we get this far, we have tried all known Requisitions
     # that opennms servers could live in.
     echo Didn\'t find Node ID >> $ERRFILE
     if [ "$ONS_HOST" != "localhost" ]
     then
        # if we can't find it, then this will create it on remote hosts.
        check_remote_ons $ONS_HOST >> $ERRFILE
        sleep 30 # allow time for node creation to complete before querying for the ID
        ONS_NODE_ID_XML=$(curl -k -m 15 -s http://$ONSUSER:$ONSPWD@${ONS_HOST}:8980/opennms/rest/nodes/OpenNMSServers:${THIS_HOST} ) 2>/dev/null
        if [ $? != 0 ]
        then
           echo CURL failure getting node id >> $ERRFILE
           exit
        fi
        ONS_NODE_ID=$(echo "$ONS_NODE_ID_XML" | xmllint --xpath '//node/@id' - | awk -F \" '{ print $2 }') 2>/dev/null
        echo Got NodeID $ONS_NODE_ID >> $ERRFILE
     else
        ONS_NODE_ID=0
     fi
  else
     if [ "$ONS_HOST" = "localhost" ]
     then
        echo check_service $REQ $ONS_HOST $MON_HOST $ONS_NODE_ID ABBCS-Heartbeat >> $ERRFILE
        check_service $REQ $ONS_HOST $MON_HOST $ONS_NODE_ID ABBCS-Heartbeat
     else
        echo check_service $REQ $ONS_HOST $MON_HOST $ONS_NODE_ID ABBCS-Stethoscope >> $ERRFILE
        check_service $REQ $ONS_HOST $MON_HOST $ONS_NODE_ID ABBCS-Stethoscope
     fi
   
  fi
 

  echo $ONS_NODE_ID
}


generate_heartbeat ()
{
   for ONS_HOST in $ONS_OUTAGE_HOSTS
   do
      ONS_NODE_ID=$(get_node_id $ONS_HOST 2>> $ERRFILE)
      if [ "$ONS_HOST" = "localhost" ]
      then
         echo Not sending heartbeat to $ONS_HOST
      else
         echo Sending heartbeat to $ONS_HOST

         if [ "$ONS_NODE_ID" = 0 ]
         then
            echo `hostname` not yet in opennms - not creating outage
         else
            echo sending heartbeat  to $ONS_HOST
            echo /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/heartbeat $ONS_HOST -n $ONS_NODE_ID -s ABBCS-Heartbeat -d \"Heartbeat event\" -p \"description not pushing up daisies\" -p \"outage $FUTURE\" -p \"notifCategory $NOTIF_CAT\"
            /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/heartbeat $ONS_HOST -n $ONS_NODE_ID -s ABBCS-Heartbeat -d "Heartbeat event" -p "description not pushing up daisies" -p "outage $FUTURE" -p "notifCategory $NOTIF_CAT" 2>> $ERRFILE
         fi
      fi
   done
}


. $CONFIG_DEFAULTS
. $CONFIG_DIR/.opennms.creds


date >> $ERRFILE
generate_heartbeat >> $ERRFILE



exit 0
