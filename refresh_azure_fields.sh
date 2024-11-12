#!/bin/bash

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

# This instance of $WORK only set when run from install_customisations.  Not required otherwise
SCRIPTS=$WORK/opt/opennms/scripts
export SCRIPTS

if [ -f /opt/opennms/.ABBCS_Config_defaults/NOT_AZURE ]
then
  echo Not Azure, exiting.
  exit 0
fi

if [ ! -d /home/opennms/var ]
then
   mkdir /home/opennms/var
fi

(
   flock -n 9 || exit 1

   WORK=/home/opennms/azure_update
   AZURE_RESOURCES_URL=http://10.2.0.99/resources.txt
   AZURE_RESOURCES=$WORK/resources.txt
   SUB_CHG_FILE=$WORK/subchange.dat
   
   CREDS=/home/opennms/etc/credentials.txt

   UPDATES=false
   
   if [ ! -d $WORK ]
   then
      mkdir $WORK
   fi
   
   if [ ! -r $CREDS ]
   then
      echo ERROR: Cannot access credentials list
      #exit 1
   fi
   
   echo 'FALSE' > $SUB_CHG_FILE

   curl $AZURE_RESOURCES_URL > $AZURE_RESOURCES

   for REQ in Servers Windows_Servers
   do
      SUB_CHANGE=$(cat $SUB_CHG_FILE)
      for SERVER_FID in $(/opt/opennms/bin/provision.pl requisition list $REQ | grep "foreign ID" | awk '{ print $2}')
      do
         SERVER=$(echo $SERVER_FID | awk -F. '{ print $1}')
         grep $SERVER $AZURE_RESOURCES | sed -e "s/^/$SERVER_FID,/"
      done | while IFS=, read SERVER_FID SUB SUBID TYPE RG NAME RESOURCEID IP COMPNAME EXCESSES 
      do
         SUB_WORK=$WORK/$SUB
   
         if [ ! -d $SUB_WORK ]
         then
            mkdir $SUB_WORK
         fi
   
         ACCESS_TOKEN_FILE=$SUB_WORK/access_token
   
         if [ ! `find $ACCESS_TOKEN_FILE -mmin -55 2>/dev/null` ]
         then
            echo no current access token for $SUB, aquiring new one
   
            grep \"$SUB\", $CREDS| sed -e 's/"//g' | while IFS=, read CSUB CACCT CPWD CTENID
            do
               echo $CSUB

               # URL Encode password field
               UPWD=$(echo $CPWD | sed 's/+/%2B/g')

               curl -X POST -d 'grant_type=client_credentials&client_id='$CACCT'&client_secret='$UPWD'&resource=https%3A%2F%2Fmanagement.azure.com%2F' https://login.microsoftonline.com/$CTENID/oauth2/token > $ACCESS_TOKEN_FILE

               ERROR=$(jq .error $ACCESS_TOKEN_FILE)

               if [ "$ERROR" != "null" ]
               then
                  ERROR_DESCRIPTION=$(jq .error_description $ACCESS_TOKEN_FILE)
                  echo Error obtaining new Azure access token:  $ERROR_DESCRIPTION
                  send-event.pl uei.opennms.org/ABBCS/Azure/failure -n $($SCRIPTS/getNodeID.sh $(hostname)) -d "Azure metric collection failure" -p "label Azure" -p "resourceId TokenID" -p "ds azureFailure" -p "description Azure access token renewal failure: $ERROR_DESCRIPTION"

               fi

            done
            SUB_CHANGE=TRUE
            echo $SUB_CHANGE>$SUB_CHG_FILE 
            echo got subscription change
         fi
         VM_INF=$SUB_WORK/$SERVER_FID
         if [ $SUB_CHANGE = 'TRUE' ]
         then
   
            ACCESS_TOKEN=$(jq .access_token $ACCESS_TOKEN_FILE | sed -e 's/"//g')
   
            curl -X GET  -H "Authorization: Bearer $ACCESS_TOKEN"  -H "Content-Type: application/json"  https://management.azure.com$RESOURCEID\?api-version=2017-12-01 > $VM_INF
            VM_SIZE=$(jq .properties.hardwareProfile.vmSize $VM_INF | sed -e 's/"//g')
            AZURE_NAME=$(jq .name $VM_INF | sed -e 's/"//g')

   
            UPDATES=$($SCRIPTS/set_asset.sh $REQ $SERVER_FID department "$SUBID")
            UPDATES=$($SCRIPTS/set_asset.sh $REQ $SERVER_FID division "$RG")
            UPDATES=$($SCRIPTS/set_asset.sh $REQ $SERVER_FID assetNumber "$RESOURCEID")
            UPDATES=$($SCRIPTS/set_asset.sh $REQ $SERVER_FID password "$ACCESS_TOKEN")
            UPDATES=$($SCRIPTS/set_asset.sh $REQ $SERVER_FID modelNumber "$VM_SIZE")
            UPDATES=$($SCRIPTS/set_asset.sh $REQ $SERVER_FID vendor "Microsoft Azure")
            UPDATES=$($SCRIPTS/set_asset.sh $REQ $SERVER_FID description "$AZURE_NAME")
            UPDATES=$($SCRIPTS/ons_add_service.sh $REQ $SERVER_FID $IP "ABBCS-Azure-Metrics")
         fi
      done
   
      if [ "$UPDATES" = "true" ]
      then
       /opt/opennms/bin/provision.pl requisition import $REQ
       sleep 10
       /opt/opennms/bin/provision.pl requisition import $REQ
      fi
  done 
   
) 9>/home/opennms/var/refresh_azure_fields.lock


