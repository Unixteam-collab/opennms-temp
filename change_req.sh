#!/bin/bash

NODE=$1
SOURCE_REQ=$2
DEST_REQ=$3

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

RRD_LOC=/opt/opennms/share/rrd/snmp/fs

NODE_XML=/tmp/node$$.xml
curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions/$SOURCE_REQ/nodes/$NODE 2> /dev/null | sed -e "s/xmlns/ignore/" | xmllint --format -  > $NODE_XML 2>&1

if [ $( grep -c "not found" $NODE_XML ) != 0 ]
then
   echo node $NODE not found
   exit
fi


#echo 'cat //node/interface/@ip-addr' | xmllint --shell $NODE_XML | awk -F\" 'NR % 2 == 0 { print $2 }'
#echo 'cat //node/category/@name' | xmllint --shell $NODE_XML | awk -F\" 'NR % 2 == 0 { print $2 }'
#echo 'cat //services/monitored-service/@service-name' | xmllint --shell $SERVICE_XML | awk -F\" 'NR % 2 == 0 { print $2 }'

/opt/opennms/bin/provision.pl node add $DEST_REQ $NODE $NODE

IPS="$(echo 'cat //node/interface/@ip-addr' | xmllint --shell $NODE_XML | awk -F\" 'NR % 2 == 0 { print $2 }')"

for IP in $IPS
do
   /opt/opennms/bin/provision.pl interface add $DEST_REQ $NODE $IP
   /opt/opennms/bin/provision.pl interface set $DEST_REQ $NODE $IP snmp-primary P

   SERVICE_XML=/tmp/service$$.xml
   curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions/$SOURCE_REQ/nodes/$NODE/interfaces/$IP/services 2> /dev/null | sed -e "s/xmlns/ignore/" | xmllint --format - > $SERVICE_XML 2> /dev/null
   SERVICES="$(echo 'cat //services/monitored-service/@service-name' | xmllint --shell $SERVICE_XML | awk -F\" 'NR % 2 == 0 { print $2 }')"

   for SERVICE in $SERVICES
   do
      /opt/opennms/bin/provision.pl service add $DEST_REQ $NODE $IP $SERVICE
   done

   rm $SERVICE_XML
done
CATEGORIES=$(echo 'cat //node/category/@name' | xmllint --shell $NODE_XML | awk -F\" 'NR % 2 == 0 { print $2 }')

echo $CATEGORY

for CATEGORY in $CATEGORIES
do
   /opt/opennms/bin/provision.pl category add $DEST_REQ $NODE $CATEGORY
done


rm $NODE_XML

mkdir -p $RRD_LOC/$DEST_REQ
mv $RRD_LOC/$SOURCE_REQ/$NODE $RRD_LOC/$DEST_REQ/$NODE
/opt/opennms/bin/provision.pl node remove $SOURCE_REQ $NODE

echo please synchronise requisitions $SOURCE_REQ and $DEST_REQ
