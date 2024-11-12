#!/bin/bash

TARGET_SERVICE=MS-RDP
SOURCE_REQ=Servers
DEST_REQ=Windows_Servers

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

NODES_XML=/tmp/nodes$$.xml

curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions/$SOURCE_REQ/nodes 2> /dev/null | sed -e "s/xmlns/ignore/" | xmllint --format -  > $NODES_XML
NODES=$(echo 'cat //nodes/node/@foreign-id' | xmllint --shell $NODES_XML | awk -F\" 'NR % 2 == 0 { print $2 }')

rm $NODES_XML

for NODE in $NODES
do

   IP=$(/opt/opennms/scripts/getNodeIP.sh $NODE)
   if [ X"$IP" = "X" ]
   then
     echo $NODE has no IP address Skipping
   else
      ID=$(/opt/opennms/scripts/getNodeID.sh $NODE)
      CHECK_WIN=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$ID/ipinterfaces/$IP/services/$TARGET_SERVICE 2>/dev/null)
      if [[ "$CHECK_WIN" == *"Monitored Service MS-RDP was not found"* ]]
      then
          echo no $TARGET_SERVICE on $NODE.  Skipping
      else
         echo found $TARGET_SERVICE on $NODE. Moving to $DEST_REQ
         /opt/opennms/scripts/change_req.sh $NODE $SOURCE_REQ $DEST_REQ
      fi
   fi
done


echo Synchronizing requisitions $SOURCE_REQ and $DEST_REQ
/opt/opennms/bin/provision.pl requisition import $SOURCE_REQ rescanExisting false
sleep 5
/opt/opennms/bin/provision.pl requisition import $SOURCE_REQ rescanExisting false
sleep 5
/opt/opennms/bin/provision.pl requisition import $DEST_REQ rescanExisting false
sleep 5
/opt/opennms/bin/provision.pl requisition import $DEST_REQ rescanExisting false

