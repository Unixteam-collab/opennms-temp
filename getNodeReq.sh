#!/bin/bash

NODE="$1"

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

REQ=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes\?limit=0 2> /dev/null | xmllint --format - | grep label | grep node | grep -w "\"$NODE" | awk -F'foreignSource="|" label="' '{ print $2 }')


if [ X"$REQ" = "X" ]
then
   echo Node Not Found >&2
   exit 1
fi
if [ "$(echo $REQ | wc -w)" -gt 1 ]
then
   echo Too many nodes match \"$NODE\"  Please be more specific
   exit 1
fi
echo $REQ
