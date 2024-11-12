#!/bin/bash


. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds


for REQUISITION in $(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions?limit=0 2> /dev/null| xmllint -format - | grep foreign-source | grep -v OpenNMSServers | awk -F\" '{ print $4}')
do


   curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions/$REQUISITION/nodes?limit=0 2>/dev/null | sed -e "s/xmlns/ignore/" | xmllint --xpath '//nodes/node/@foreign-id | //nodes/node/interface/@ip-addr' --format - |sed -e "s/foreign/\n&/g" | while read NODE IP
   do
     NODE=$(echo $NODE | cut -d\" -f2 )
     IP=$(echo $IP | cut -d\" -f2)
     echo
     echo -n $NODE $IP
     provision.pl snmp get $IP | while read a b c
     do
        if [ $b = "community:" ]
        then
           echo -n "" $c
        fi
        if [ $b = "proxyHost:" ]
        then
           echo -n "" $c
        fi
     done

   done
done

   
