#!/bin/bash

#   20-11-2019    Modified to protect xmllint from xmlns tags in the wmi-config.xml file


NODE_IP=$1
shift
SERVICE="$*"


OUTPUT=""

#echo "$NODE_IP $SERVICE" >> /tmp/service.txt

WMI_CONFIG="$(cat /opt/opennms/etc/wmi-config.xml  | sed -e "s/xmlns/ignore/" )"

get_wmi_creds()
{
   # look for specific config
   USER=$(echo "$WMI_CONFIG" | xmllint --xpath "/wmi-config/definition[specific=\"$NODE_IP\"]/@username" - 2>/dev/null)
# xmllint --xpath "string(/wmi-config/definition[range/begin[text() < \"$NODE_IP\"] and range/end[text() > \"$NODE_IP\"]]/@username)" $WMI_CONFIG 

 

   if [ $? == 0 ]
   then
      DOMAIN=$(echo "$WMI_CONFIG" | xmllint --xpath "/wmi-config/definition[specific=\"$NODE_IP\"]/@domain" - 2>/dev/null)
      PASSWORD=$(echo "$WMI_CONFIG" | xmllint --xpath "/wmi-config/definition[specific=\"$NODE_IP\"]/@password" - 2>/dev/null)
   else
      # Specific config not found.  Look for range
      RANGE_FOUND=0
      for RANGE in $(echo "$WMI_CONFIG" | xmllint --xpath "/wmi-config/definition/range/@begin" - 2>/dev/null)
      do
         START=$(echo $RANGE | cut -d\" -f2)
         END=$(echo "$WMI_CONFIG" | xmllint --xpath "/wmi-config/definition[range/@begin=\"$START\"]/range/@end" - 2>/dev/null | cut -d\" -f2)
         CHECK_IP=$(echo "$START
$END
$NODE_IP" | sort -V | tail -2 | head -1)
         if [ $NODE_IP = $CHECK_IP ]
         then
            RANGE_FOUND=$START
            break
         fi
      done
      if [ $RANGE_FOUND = 0 ]
      then
         # Range not found.  Use global config
         USER=$(echo "$WMI_CONFIG" | xmllint --xpath "string(/wmi-config/@username)" - 2>/dev/null)
         DOMAIN=$(echo "$WMI_CONFIG" | xmllint --xpath "string(/wmi-config/@domain)" - 2>/dev/null)
         PASSWORD=$(echo "$WMI_CONFIG" | xmllint --xpath "string(/wmi-config/@password)" - 2>/dev/null)
      else
         # Range found.  Use range config
         USER=$(echo "$WMI_CONFIG" | xmllint --xpath "string(/wmi-config/definition[range/@begin=\"$RANGE_FOUND\"]/@username)" - 2> /dev/null)
         DOMAIN=$(echo "$WMI_CONFIG" | xmllint --xpath "string(/wmi-config/definition[range/@begin=\"$RANGE_FOUND\"]/@domain)" - 2> /dev/null)
         PASSWORD=$(echo "$WMI_CONFIG" | xmllint --xpath "string(/wmi-config/definition[range/@begin=\"$RANGE_FOUND\"]/@password)" - 2> /dev/null)
      fi
   fi

}

check_wmi ()
{
   # usage: check_wmi $NODE_IP $DOMAIN $USER $PASSWORD "$SERVICE"
#   /opt/opennms/bin/checkwmi -wmiClass "Win32_Service" -wmiObject "State" -wmiWql "Select State From Win32_Service Where DisplayName='$5'" -op "EQ" -value "Running" -matchType "all" -domain "$2" "$1" "$3" "$4" 2> /dev/null
#   echo /bin/wmic -U \"$2\\$3%$4\" //$NODE_IP \"Select DisplayName,State From Win32_Service Where DisplayName=\'$5\'\" >> /tmp/checkwmi.out 2>&1
#   /bin/wmic -U "$2\\$3%$4" //$NODE_IP "Select DisplayName,State From Win32_Service Where DisplayName='$5'" | tee -a /tmp/checkwmi.out
   /bin/wmic -U "$2\\$3%$4" //$NODE_IP "Select DisplayName,State From Win32_Service Where DisplayName='$5'" 2>&1

   return $?
}


get_wmi_creds

CHECK_WMI="$(check_wmi $NODE_IP $DOMAIN $USER "$PASSWORD" "$SERVICE" )"

RES=$?

if [ $RES != 0 ]
then
#   OUTPUT="$OUTPUT\\\\n$(echo 1st try failed)"
#   OUTPUT="$OUTPUT\\\\n$(echo "$CHECK_WMI" | sed -e "s/'//g")"
#   OUTPUT="$OUTPUT\\\\n$(echo trying again in 5 seconds)"

   sleep 5
   
   CHECK_WMI="$(check_wmi $NODE_IP $DOMAIN $USER $PASSWORD "$SERVICE" )"
  # CHECK_WMI="$(/opt/opennms/bin/checkwmi -wmiClass "Win32_Service" -wmiObject "State" -wmiWql "Select State From Win32_Service Where DisplayName='$SERVICE'" -op "EQ" -value "Running" -matchType "all" -domain GMS $NODE_IP svc-opennms a88wM1M0nt1t0r1n6 2> /dev/null)"
   RES=$?
   if [ $RES != 0 ]
   then
      OUTPUT="$OUTPUT\\\\n$(echo "Error querying WMI")"
#      OUTPUT="$OUTPUT\\\\n$(echo "$CHECK_WMI" | sed -e "s/'//g")"
   fi
fi

OUTPUT="$OUTPUT\\\\n$CHECK_WMI"
echo -n "$OUTPUT" | sed -e "s/'//g" | sed ':a;N;$!ba;s/\n/\\\\n/g'

