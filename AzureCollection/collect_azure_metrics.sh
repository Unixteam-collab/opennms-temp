#!/bin/bash

if [ -f /opt/opennms/.ABBCS_Config_defaults/NOT_AZURE ]
then
  echo Not Azure, exiting.
  exit 0
fi


(
   flock -n 9 || exit 1
   
   BIN=/opt/opennms/scripts/AzureCollection
   . $BIN/config.sh
   
   
   CREDS=/home/opennms/etc/credentials.txt
   
   if [ ! -d $WORK ]
   then
      mkdir $WORK
   fi
   
   if [ ! -r $CREDS ]
   then
      echo ERROR: Cannot access credentials list
      #exit 1
   fi
   
   if [ ! -d $METRIC_STOR ]
   then
      mkdir -p $METRIC_STOR
   fi
   
   curl -m $TIMEOUT $AZURE_RESOURCES_URL > $AZURE_RESOURCES
   for REQ in Servers Windows_Servers
   do
      for SERVER_FID in $(/opt/opennms/bin/provision.pl requisition list $REQ | grep "foreign ID" | awk '{ print $2}')
      do
         SERVER=$(echo $SERVER_FID | awk -F. '{ print $1}')
         grep $SERVER $AZURE_RESOURCES | sed -e "s/^/$SERVER_FID,/"
      done | while IFS=, read SERVER_FID SUB SUBID TYPE RG NAME RESOURCEID IP COMPNAME EXCESSES 
      do
         METRIC_FILE=$METRIC_STOR/azure_$IP.xml
   
         SUB_WORK=$WORK/$SUB
         WORK_FILE=$WORK/.mertic.$IP
   
         if [ ! -d $SUB_WORK ]
         then
            mkdir $SUB_WORK
         fi
   
         ACCESS_TOKEN_FILE=$SUB_WORK/access_token
   
      ########
      #  This function is performed in /opt/opennms/scripts/refresh_azure_fields.sh
      ########
      #   if [ ! `find $ACCESS_TOKEN_FILE -mmin -55 ` ]
      #   then
      #      echo no current access token for $SUB, aquiring new one
      #
      #      grep \"$SUB\", $CREDS| sed -e 's/"//g' | while IFS=, read CSUB CACCT CPWD CTENID
      #      do
      #         echo $CSUB
      #         curl -m $TIMEOUT -X POST -d 'grant_type=client_credentials&client_id='$CACCT'&client_secret='$CPWD'&resource=https%3A%2F%2Fmanagement.azure.com%2F' https://login.microsoftonline.com/$CTENID/oauth2/token > $ACCESS_TOKEN_FILE 
      #      done
      #   fi
   
         VM_INF=$SUB_WORK/$SERVER_FID
   
   
         ACCESS_TOKEN=$(jq .access_token $ACCESS_TOKEN_FILE | sed -e 's/"//g')
         export ACCESS_TOKEN VM_INF
   
   
         echo $SERVER_FID
   
         echo "<metrics>" > $WORK_FILE
   
         $BIN/collect_bseries.sh  $RESOURCEID >> $WORK_FILE
   
         echo "</metrics>" >> $WORK_FILE
         mv $WORK_FILE $METRIC_FILE
   
      done
   done

   find $METRIC_STOR -type f -mmin +10 -exec rm {} \;

   # run scripts not driven from nodes in opennms
   # 
   # ASR monitoring - driven from Replication stats for recovery vault
   if [ -f /home/opennms/etc/check_asr.conf ]
   then
      . /home/opennms/etc/check_asr.conf
      SUB_WORK=$WORK/$SUBSCRIPTIONNAME
   
      ACCESS_TOKEN_FILE=$SUB_WORK/access_token
      ACCESS_TOKEN=$(jq .access_token $ACCESS_TOKEN_FILE | sed -e 's/"//g')
      export ACCESS_TOKEN 

      /opt/opennms/scripts/AzureCollection/check_asr.sh $SUBSCRIPTIONID $RESOURCEGROUP $VAULT   
   fi
   
) 9>/home/opennms/var/collect_azure_metrics.lock
