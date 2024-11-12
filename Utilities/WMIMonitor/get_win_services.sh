#!/bin/bash

#   20-11-2019    Modified to protect xmllint from xmlns tags in the wmi-config.xml file


NODE_IP=$1

. /opt/opennms/scripts/Utilities/WMIMonitor/get_wmi_creds.sh $NODE_IP

echo $USER
echo $DOMAIN
echo $PASSWORD

check_wmi ()
{
   # usage: check_wmi $NODE_IP $DOMAIN $USER $PASSWORD "$SERVICE"
#   /opt/opennms/bin/checkwmi -wmiClass "Win32_Service" -wmiObject "State" -wmiWql "Select State From Win32_Service Where DisplayName='$5'" -op "EQ" -value "Running" -matchType "all" -domain "$2" "$1" "$3" "$4" 2> /dev/null
#   echo /bin/wmic -U \"$2\\$3%$4\" //$NODE_IP \"Select DisplayName,State From Win32_Service Where DisplayName=\'$5\'\" >> /tmp/checkwmi.out 2>&1
#   /bin/wmic -U "$2\\$3%$4" //$NODE_IP "Select DisplayName,State From Win32_Service Where DisplayName='$5'" | tee -a /tmp/checkwmi.out
echo   /bin/wmic -U "$2\\$3%$4" //$NODE_IP "Select DisplayName,State From Win32_Service "
   /bin/wmic -U "$2\\$3%$4" //$NODE_IP "Select DisplayName,State From Win32_Service "

   return $?
}


CHECK_WMI="$(check_wmi $NODE_IP $DOMAIN $USER "$PASSWORD" "$SERVICE")"

RES=$?

if [ $RES != 0 ]
then
   echo 1st try failed:
   echo "$CHECK_WMI"
   echo trying again in 5 seconds
   sleep 5
   
   CHECK_WMI="$(check_wmi $NODE_IP $DOMAIN $USER $PASSWORD "$SERVICE")"
  # CHECK_WMI="$(/opt/opennms/bin/checkwmi -wmiClass "Win32_Service" -wmiObject "State" -wmiWql "Select State From Win32_Service Where DisplayName='$SERVICE'" -op "EQ" -value "Running" -matchType "all" -domain GMS $NODE_IP svc-opennms a88wM1M0nt1t0r1n6 2> /dev/null)"
   RES=$?
   if [ $RES != 0 ]
   then
      echo "Error querying WMI"
      echo "$CHECK_WMI"
   fi
fi

echo "$CHECK_WMI"
