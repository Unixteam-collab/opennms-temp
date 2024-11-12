#!/bin/bash

NODE="$1"

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

NODE_ID=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes\?limit=0 2> /dev/null | xmllint --format - | grep label | grep node | grep -w "\"$NODE" | awk -F'id="|" type="' '{ print $2 }' )

if [ X"$NODE_ID" = "X" ]
then
   echo Node Not Found >&2
   exit 1
fi
if [ "$(echo $NODE_ID | wc -w)" -gt 1 ]
then
   echo Too many nodes match \"$NODE\"  Please be more specific
   exit 1
fi
echo $NODE_ID
