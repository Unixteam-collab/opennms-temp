#!/bin/bash

# add a service to a node if not already there

  # Parameters:
  #   1: "Requistion"
  #   2: "ForeignID"
  #   3: "IP"
  #   4: "Service"
  #  eg:
  #        add_service Servers $SERVER_FID $IP "ABBCS_Azure_Metric"

REQUISITION="$1"
FID="$2"
IP="$3"
SERVICE="$4"

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds
CHANGED=false

CURRENT_SRV=$(curl "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes/$REQUISITION:$FID/ipinterfaces/$IP/services/$SERVICE" 2>/dev/null| xmllint --xpath "string(//name)" - 2>/dev/null) 

if [ "$CURRENT_SRV" != "$SERVICE" ]
then
     /opt/opennms/bin/provision.pl service add $REQUISITION $FID $IP "$SERVICE"
     CHANGED=true
fi
echo $CHANGED

