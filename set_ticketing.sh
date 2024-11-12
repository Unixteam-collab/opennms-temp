#!/bin/bash

CONFIG_FILE=/opt/opennms/.ABBCS_Config_defaults/defaults

if grep -e 'USE_OPSGENIE="false"' $CONFIG_FILE > /dev/null
then
  echo Activating OpsGenie notification
  sed -i 's/USE_OPSGENIE="false"/USE_OPSGENIE="true"/' $CONFIG_FILE
  
#  HOSTNAME=$(hostname)

#  NODEID=$(/opt/opennms/scripts/getNodeID.sh $HOSTNAME)

#  if [ "$NODEID" != "Node Not Found" ]
#  then
#     /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/event localhost -n $NODEID -x 4 -d "ABBCS OpsGenie Activation" -p "description OpsGenie Activation"  -p "message OpsGenie ticket submission has been activated for $HOSTNAME.  Please DO NOT close this ticket in Remedy Force until you have confirmed OpsGenie ticket submission is working for this OpenNMS server.  If OpsGenie Tickets are not working, then please use this ticket to track the work to fix."  
#  fi
else
  echo OpsGenie notification already set.
fi

if grep -e 'USE_RF="true"' $CONFIG_FILE > /dev/null
then
  echo Deactivating Remedy Force notification
  sed -i 's/USE_RF="true"/USE_RF="false"/' $CONFIG_FILE
  
else
  echo Remedy Force notification already deactivated.
fi
