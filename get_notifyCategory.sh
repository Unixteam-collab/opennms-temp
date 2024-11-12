#!/bin/bash


HOST=$1

. /opt/opennms/.ABBCS_Config_defaults/defaults
. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

# $WORK is only defined in install_customisations.sh when installing updates
NODEID=$($WORK/opt/opennms/scripts/getNodeID.sh $HOST)

NOTIFCAT=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$NODEID/assetRecord 2>/dev/null| xmllint --xpath "string(//notifyCategory)" - )


if [ "$NOTIFCAT" = "" ]
then
   NOTIFCAT=$ENV_TYPE
fi

echo $NOTIFCAT
