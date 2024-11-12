#!/bin/bash

# this script is for use to divert Windows, DB and  Comms alerts away from the Unix team.

NODE="$1"
CURR_CAT="$2"


if [ "$CURR_CAT" == 'Operating System' -o "$CURR_CAT" == 'UNIX' ]
then
   . /opt/opennms/.ABBCS_Config_defaults/defaults
   . /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

   NODE_ID=$(/opt/opennms/scripts/getNodeID.sh $NODE 2>/dev/null)

   CATEGORIES=$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/categories/nodes/$NODE_ID 2>/dev/null| xmllint --format - 2>/dev/null | grep name)


   NEW_CAT=$(echo "$CATEGORIES" | grep category | while read a b i
    do
      CAT=$(echo $i | awk -F \" '{ print $2 }')

      case "$CAT" in
        Microsoft )
           echo Window
           break
           ;;
        Routers|Switches|firewall )
           echo Network
           break
           ;;
        Databases )
           echo Database
           break
           ;;
      esac
    done)
   
   if [ "$NEW_CAT" != "" ]
   then
      CATEGORY="$NEW_CAT"
   else
      CATEGORY="$CURR_CAT"
   fi
else
   CATEGORY="$CURR_CAT"
fi

echo "$CATEGORY"
