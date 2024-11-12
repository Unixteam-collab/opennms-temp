#/bin/bash

# Parameters:
#   1: "Requistion"
#   2: "ForeignID"
#   3: "Asset Field"
#   4: "value" 
#  eg:
#        set_asset.sh Servers $SERVER_FID department "$SUBID"

REQUISITION="$1"
FID="$2"
FIELD="$3"
VALUE="$4"
 
. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds


CHANGED=false

CURRENT_VAL=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$REQUISITION:$FID/assetRecord | xmllint --xpath "string(//$FIELD)" - )
if [ "$CURRENT_VAL" != "$VALUE" ]
then
  /opt/opennms/bin/provision.pl asset set "$REQUISITION" "$FID" "$FIELD" "$VALUE"
  CHANGED=true
fi

echo $CHANGED
