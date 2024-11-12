#!/bin/bash

NODE="$1"

. /opt/opennms/.ABBCS_Config_defaults/defaults
. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

NODETYPE=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$NODE 2>/dev/null| xmllint --xpath "string(/node/assetRecord/notifyCategory)" - 2>/dev/null)




if [ X"$NODETYPE" = "X" ]
then
   NODETYPE="$ENV_TYPE"
fi
echo $NODETYPE
