#!/bin/bash

NODE="$1"

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

NODE_NAME=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$1 2>/dev/null | xmllint --xpath "string(//@label)" - )


if [ X"$NODE_NAME" = "X" ]
then
   echo Node Not Found >&2
   exit 1
fi
echo $NODE_NAME
