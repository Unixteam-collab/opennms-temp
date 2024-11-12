#!/bin/bash

. /opt/opennms/.ABBCS_Config_defaults/defaults
. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

FOREIGN_SOURCE=$1
POLICY=$2

NOTFOUND=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/foreignSources/$FOREIGN_SOURCE/policies/$POLICY | grep -c "not found")

if [ "$NOTFOUND" = "0" ]
then
   echo Policy in place already
else
   echo missing policy

   POLICY_DATA='<policy name="RFNotification" class="org.opennms.netmgt.provision.persist.policies.NodeCategorySettingPolicy">
    <parameter key="category" value="RFNotification"/>
    <parameter key="matchBehavior" value="ALL_PARAMETERS"/>
  </policy>'

   POLFILE=/tmp/policyfile.tmp
   echo $POLICY_DATA>$POLFILE

   echo 'curl -v -H "Content-Type: application/x-www-form-urlencoded" -d ' @$POLFILE -X POST http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/foreignSources/$FOREIGN_SOURCE/policies/$POLICY
   curl -v -H "Content-Type: application/x-www-form-urlencoded" -d \@$POLFILE -X POST http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/foreignSources/$FOREIGN_SOURCE/policies/$POLICY

fi


