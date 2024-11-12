#!/bin/bash

NODE=$1

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

NODE_ID=$(/opt/opennms/scripts/getNodeID.sh $NODE)

if [ $? = 0 ]
then
   curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$NODE_ID/ipinterfaces\?limit=0 2> /dev/null | xmllint --xpath '//ipInterfaces/ipInterface[contains(@snmpPrimary,"P")]/ipAddress/text()' -
   echo

   exit 0
else
   exit 1
fi


