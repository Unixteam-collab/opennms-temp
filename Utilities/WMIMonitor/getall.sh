#!/bin/bash

NODE_IP=$1


OPENNMS_HOME=/opt/opennms
WMIUTIL_BASE=$OPENNMS_HOME/scripts/Utilities/WMIMonitor

. $WMIUTIL_BASE/get_wmi_creds.sh $NODE_IP


$WMIUTIL_BASE/get_win_services.sh $NODE_IP
