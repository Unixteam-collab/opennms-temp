#!/bin/bash

#
#  Program:   ons_outage.sh
#
#  Purpose:   To create an outage for suppression of events from OpenNMS server
#             To be used when opennms is restarted.
#
#  Author:   John Blackburn
#
#  Version:  1.6
#
#  History:  1.0  JDB 2017-12-05  Initial Revision - code migrated out of install_customisations.sh
#            1.1  JDB 2017-12-08  Simplified code to determine node ID on remote server
#            1.2  JDB 2017-12-11  Code change from 1.1 broke case where multiple domains are defined
#                                 Modified to correctly handle multipe domain case.
#            1.3  JDB 2018-01-03  Added parameter for outage length (defaults to 15 minutes if not specified)
#            1.4  JDB 2018-07-09  Fixed LOGDIR parameters, and decoding of curl output
#            1.5  JDB 2020-02-25  Updated for heartbeat monitor
#            1.6  JDB 2020-03-05  Defined $HOME to assist execution from Spacewalk
#
#  command needed for heartbeat monitor outage update
#  touch -t $(date -d "10 min" "+%Y%m%d%H%M") test
#

OBSOLETE_FILES="/opt/opennms/etc/events/AlarmChangeNotifierEvents.xml"

OPENNMS_BASE=/opt/opennms
OPENNMS_HOMEDIR=/home/opennms
LOGDIR=$OPENNMS_HOMEDIR/logs
LOGFILE=$LOGDIR/config_update.log
ERRFILE=$LOGDIR/config_update.err
CONFIG_DIR=${OPENNMS_BASE}/.ABBCS_Config_defaults
CONFIG_DEFAULTS=${CONFIG_DIR}/defaults

if [ ! -v HOME ]
then
   HOME=$OPENNMS_HOMEDIR
fi
export HOME

. $WORK/$CONFIG_DIR/.opennms.creds

# Default Length of outage in Minutes
OUTAGE_LENGTH=15


usage() {
   echo "Usage: $0 [time] " >&2
   echo "   time is an optional integer parameter specifying outage length (in minutes) - default is 15" >&2
   exit 1
}


check_remote_ons ()
{
   ONS_HOST=$1

   FS="OpenNMSServers"
   HOST=$(hostname)
   FSID="$FS:$HOST"
   MY_IP=$(hostname -I | head -1 | cut -d\  -f1)
   echo checking Remote Monitor $ONS_HOST

   # Check if the "$FS" requisition exists.  If not, create it.
   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest requisition list $FS

   if [ $? != 0 ]
   then
      echo Creating Requisition \"$FS\ on $ONS_HOST"
      /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest requisition add $FS
   else
      echo Found Requisition \"$FS\ on $ONS_HOST"
   fi


   if [ ! -v SNMP_COMMUNITY ]
   then
     /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest snmp set $IP_ADDR $SNMP_COMMUNITY
   fi

   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest node add $FS $HOST $HOST
   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest interface add $FS $HOST $MY_IP
   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest interface set $FS $HOST $MY_IP snmp-primary P
   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest service add $FS $HOST $MY_IP ABBCS-Stethoscope

   /opt/opennms/bin/provision.pl --url http://$ONS_HOST:8980/opennms/rest requisition import $FS

}

get_node_id()
{


  ONS_HOST=$1
  THIS_HOST=$(hostname)

  for REQ in Servers OpenNMSServers
  do
     FS=$REQ
     for DOM in "" $(for i in $DOMAIN; do echo ".$i"; done)
     do
        # get ONS Node ID for automatic outage
        ONS_NODE_ID=$(curl -s http://$ONSUSER:$ONSPWD@${ONS_HOST}:8980/opennms/rest/nodes/Servers:${THIS_HOST}${DOM} 2>/dev/null| xmllint --xpath '//node/@id' - 2>/dev/null| awk -F \" '{ print $2 }') 2>/dev/null

        if [ "${ONS_NODE_ID}X" != "X" ]
        then
           break
        fi
     done
     if [ "${ONS_NODE_ID}X" != "X" ]
     then
        break
     fi
  done

  if [ "${ONS_NODE_ID}X" = "X" ]
  then 
     # For new server, there will not yet be a node in opennms.  If we get this far, we have tried all known Requisitions
     # that opennms servers could live in.
     if [ "$ONS_HOST" != "localhost" ]
     then
        # if we can't find it, then this will create it on remote hosts.
        check_remote_ons $ONS_HOST >> $ERRFILE
        sleep 30 # allow time for node creation to complete before querying for the ID
        ONS_NODE_ID=$(curl -s http://$ONSUSER:$ONSPWD@${ONS_HOST}:8980/opennms/rest/nodes/OpenNMSServers:${THIS_HOST} | xmllint --xpath '//node/@id' - | awk -F \" '{ print $2 }') 2>/dev/null
     else
        ONS_NODE_ID=0
     fi
  fi

  echo $ONS_NODE_ID
}



# create a 15 minute outage for opennms so that restart doesn't raise RF tickets
create_ons_outage ()
{
   for ONS_HOST in $ONS_OUTAGE_HOSTS
   do

      echo Processing outage on $ONS_HOST
      ONS_NODE_ID=$(get_node_id $ONS_HOST) 2>/dev/null


      if [ "$ONS_HOST" = "localhost" ]
      then
         ONS_OUTAGE_NAME="OpenNMSConfigUpdate"
      else
         ONS_OUTAGE_NAME="OpenNMSConfigUpdate-$(hostname)"
      fi
      if [ "$ONS_NODE_ID" = 0 ]
      then
         echo `hostname` not yet in opennms - not creating outage
      else
         echo Creating outage $ONS_OUTAGE_NAME on $ONS_HOST

         # Heartbeat outage send event command

         echo curl http://$ONSUSER:ONSPWD@$ONS_HOST:8980/opennms/rest/categories/SNMP/nodes/$ONS_NODE_ID >> $ERRFILE
         SNMP_CHECK="$(curl http://$ONSUSER:$ONSPWD@$ONS_HOST:8980/opennms/rest/categories/SNMP/nodes/$ONS_NODE_ID 2>>$ERRFILE)"
         echo SNMP_CHECK=$SNMP_CHECK >> $ERRFILE
         if [[ "$SNMP_CHECK" == "Can't find category SNMP for node"* ]]
         then
            echo no SNMP so rely on heartbeat outage 
         else
            echo found SNMP so setting up outage

            # Extract localtime from remote OpenNMS host 
            rdatestring=$( snmpget -v2c -c OpenNMSMon $ONS_HOST HOST-RESOURCES-MIB::hrSystemDate.0 2>>$ERRFILE | gawk '{print $NF}' )

            #  if nothing returned, then just use local time
            if [ ! "$rdatestring" ] ; then
               OUTAGE_START=$(date "+%d-%b-%Y %H:%M:%S")
            else
               # Convert SNMP datetime to unix datetime
               rdate=$( echo $rdatestring | gawk -F',' '{print $1}' )
               rtime=$( echo $rdatestring | gawk -F',' '{print $2}' | gawk -F'.' '{print $1}' )
               cldate=$( echo $rdate | gawk -F'-' '{printf("%4i",$1)}; {printf("%02i",$2)}; {printf("%02i",$3)};' )
               cltime=$( echo $rtime | gawk -F':' '{printf("%02i",$1)}; {printf("%02i",$2)}; {printf(" %02i",$3)};' )
               OUTAGE_START=$( date -d "$cldate $cltime sec" "+%d-%b-%Y %H:%M:%S" )
            fi
            OUTAGE_END=$(date -d "$OUTAGE_START $OUTAGE_LENGTH min" "+%d-%b-%Y %H:%M:%S")
            BODY='<?xml version="1.0"?>
              <outage name="'$ONS_OUTAGE_NAME'" type="specific">
              <time begins="'$OUTAGE_START'" ends="'$OUTAGE_END'" />
              <node id ="'$ONS_NODE_ID'" />
              </outage>'

            curl -s -X DELETE "http://$ONSUSER:$ONSPWD@$ONS_HOST:8980/opennms/rest/sched-outages/$ONS_OUTAGE_NAME/notifd"
            curl -s -X DELETE "http://$ONSUSER:$ONSPWD@$ONS_HOST:8980/opennms/rest/sched-outages/$ONS_OUTAGE_NAME"
            sleep 5
            echo Creating $ONS_OUTAGE_NAME schedule
            curl -s -X POST -H 'Content-type: application/xml' -d "$BODY" "http://$ONSUSER:$ONSPWD@$ONS_HOST:8980/opennms/rest/sched-outages" 2>&1 >> $ERRFILE
            sleep 5
            echo linking $ONS_OUTAGE_NAME to notifd
            curl -s -X PUT "http://$ONSUSER:$ONSPWD@$ONS_HOST:8980/opennms/rest/sched-outages/$ONS_OUTAGE_NAME/notifd" 2>&1 >> $ERRFILE

            sleep 5
         fi
      fi
   done
}


if [ $# = 1 ]
then
   OUTAGE_LENGTH=$1
   re='^[0-9]+$'
   if ! [[ $OUTAGE_LENGTH =~ $re ]] 
   then
      echo "error: outage Lenght must be a number" >&2
      usage
      exit 1
   fi
elif [ $# != 0 ]
then
   echo "error: incorrect number of parameters" >&2
   usage
   exit 1
fi


. $CONFIG_DEFAULTS


date >> $ERRFILE

#New method with heartbeat (this needs to be run before the defined outage, otherwise the defined outage will prevent
# the heatbeat capture notification from running
#
echo pausing heartbeat monitor
# $WORK is only defined in install_customisations.sh when installing updates
$WORK/opt/opennms/scripts/heartbeat.sh $OUTAGE_LENGTH
# bump the age of any heartbeat files so that outage on this host does not cause heartbeat processing to pause.
if [ "$(ls -A /home/opennms/var/heartbeats)" ]
then
   for hb_hosts in /home/opennms/var/heartbeats/*
   do
      echo Bumping heartbeat timestamp for $hb_host >> $ERRFILE
      touch -t $(date -d "$OUTAGE_LENGTH min" "+%Y%m%d%H%M") $hb_hosts
   done
fi
   

# Old method with defined outage
create_ons_outage


exit 0
