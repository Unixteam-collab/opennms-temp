#!/bin/bash

if [ $# != 3 ]
then
   echo "Usage:  $0 SUBSCRIPTIONID RG VAULT"
   echo
   echo ACCESS_TOKEN needs to be set to the current access token for this subscription
   echo 
   echo To run automatically, create /home/opennms/etc/check_asr.conf containing the following:
   echo
   echo 'SUBSCRIPTIONNAME=<subscription Name>'
   echo 'SUBSCRIPTIONID=<subscription ID>'
   echo 'RESOURCEGROUP=<Resource Group>'
   echo 'VAULT=<Recovery Vault>'
   echo 'export SUBSCRIPTIONNAME SUBSCRIPTIONID RESOURCEGROUP VAULT'
   echo
   echo eg:
   echo SUBSCRIPTIONNAME=CS-APAC-DR-ABC
   echo SUBSCRIPTIONID=55111187-269a-48b7-b7ee-c78cac3764c3
   echo RESOURCEGROUP=DR-Ellipse-PRD
   echo VAULT=azu_Ellipse_Vault01
   echo 'export SUBSCRIPTIONNAME SUBSCRIPTIONID RESOURCEGROUP VAULT'
   echo 
   echo Crontab entry should exist for opennms user to run /opt/opennms/scripts/AzureCollection/collect_azure_metrics.sh at a relevant interval
   exit 1
fi

SUBSCRIPTION=$1
RESOURCEGROUP=$2
VAULT=$3


ASR_INFO=/home/opennms/var/asr_$VAULT.json


 
#URI=/subscriptions/55111187-269a-48b7-b7ee-c78cac3764c3/resourceGroups/DR-Ellipse-PRD/providers/Microsoft.RecoveryServices/vaults/azu-Ellipse-Vault01/replicationProtectedItems?api-version=2016-08-10 
URI=/subscriptions/$SUBSCRIPTION/resourceGroups/$RESOURCEGROUP/providers/Microsoft.RecoveryServices/vaults/$VAULT/replicationProtectedItems?api-version=2016-08-10 

#echo URI="$URI"


curl -X GET -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" https://management.azure.com$URI > $ASR_INFO


#VMLIST=$(jq '.value | .. | .properties? .friendlyName | select (. != null)' $ASR_INFO | sed -e 's/"//g')

for ASR_ROW in $(jq -c '.value | .[] | @base64' $ASR_INFO)
do
   _jq () {
      echo ${ASR_ROW} | sed -e 's/"//g' | base64 --decode | jq -r "${1}"
   }
   VMNAME=$(_jq '.properties.friendlyName')
   RESOURCE_ID=$(_jq '.properties.providerSpecificDetails.fabricObjectId')
   PROTECTION_STATE=$(_jq '.properties.protectionState')
   REPLICATION_HEALTH=$(_jq '.properties.replicationHealth')

   
   if [ "$PROTECTION_STATE" != 'Protected' -o "$REPLICATION_HEALTH" != 'Normal' ]
   then
      REPLICATION_ERRORS="$(_jq '.properties.replicationHealthErrors | .[0] |.errorMessage' | tr -d \"\' )"
      echo "Replication issue for $VMNAME"
      echo Error message $REPLICATION_ERRORS
      ONS_ID="$(curl -s http://admin:kntEof3EH6BDgtnPaBNU@localhost:8980/opennms/rest/nodes | xmllint --xpath 'string(/nodes/node[assetRecord/description='\"$VMNAME\"']/@id)' -)"
      echo raise call against $ONS_ID
      /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/MSSQL/replication-failure localhost -n $ONS_ID -d "Replication error" -p "label Replication" -p "resourceId ${VMNAME}_ASR" -p "ds ASRFailure" -p "description Replication error: $REPLICATION_ERRORS"  


   else
      echo "Replication for $VMNAME is good"
   fi

   
done


 
