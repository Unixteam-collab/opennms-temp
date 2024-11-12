#!/bin/bash

#
# Program Name: cmdb_extract.sh
#
# Purpose:      extract  node names in format suitable for RemedyForce CI creation
#
# Author:       John Blackburn
#
# Description:  List monitored VM's in format suitable for RemedyForce CI Creation
#               Output of this script should be used to populate spreadsheet for submission to RF team
#
#
#
# Version:      1.0
#              
# History:      2017-12-05 JDB 1.0  Initial revision
#              

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds


for REQUISITION in $(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions?limit=0 2> /dev/null| xmllint -format - | grep foreign-source | grep -v OpenNMSServers | awk -F\" '{ print $4}')
do

  for NODE in $(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/requisitions/$REQUISITION/nodes?limit=0 2> /dev/null | xmllint --format - | grep foreign-id | awk -F\" '{ print $4 }')
  do
    echo $NODE $(echo $NODE | tr [:lower:] [:upper:])
  done
done




