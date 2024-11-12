#!/bin/bash

if [ "$_GOT_WMI_CONFIG" = "$1" ]
then
   echo got it
else
   echo not got it
   _GOT_WMI_CONFIG=$1
   export _GOT_WMI_CONFIG

   NODE_IP=$1

   WMI_CONFIG="$(cat /opt/opennms/etc/wmi-config.xml  | sed -e "s/xmlns/ignore/" )"

   # look for specific config
   USER=$(echo "$WMI_CONFIG" | xmllint --xpath "/wmi-config/definition[specific=\"$NODE_IP\"]/@username" - 2>/dev/null)
 

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
fi

export USER DOMAIN PASSWORD
