#!/bin/bash


NODE_IP=$1

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
   /bin/wmic -U "$2\\$3%$4" //$NODE_IP "Select Status From Win32_BIOS" > /dev/null 2>&1
#CLASS: Win32_BIOS
#Name|SoftwareElementID|SoftwareElementState|Status|TargetOperatingSystem|Version
#Intel(R) Xeon(R) CPU E5-2673 v4 @ 2.30GHz|Intel(R) Xeon(R) CPU E5-2673 v4 @ 2.30GHz|3|OK|0|VRTUAL - 6001702


   return $?
}


get_wmi_creds

CHECK_WMI="$(check_wmi $NODE_IP $DOMAIN $USER "$PASSWORD" )"

RES=$?

if [ $RES != 0 ]
then
   #echo 1st try failed
   #echo "$CHECK_WMI"
   #echo trying again in 5 seconds
   sleep 5
   
   CHECK_WMI="$(check_wmi $NODE_IP $DOMAIN $USER "$PASSWORD" )"
   RES=$?
   if [ $RES != 0 ]
   then
      echo "WMI not found"
      exit 1
   fi
fi

echo "WMI found"
exit 0
