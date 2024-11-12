#!/bin/bash
#
#***************URL monitoring by Sadish Nambiar - v2******************
# 11/06/2020
#***History***
# This script is written to cope monitoring for Appliance structure for now. 
# Does not support Azure client, also believe there is already HTTP monitoring for it.
# 
#09/09/2021		Enhance script to cater appliance with more than standard deploy 
#			e.g WPC where we have 10 vms/url to monitor in single appliance 
#15/09/2021		Changed syntax to not count empty lines. Included logging option
#			as well when issue detected.

TARGETDEVICEID1=$1       # Single CI to raise againts which should be appliance itself
applianceHOST=$2         # Appliance hostname or IP

response=$(ssh -nq opennms@"$applianceHOST" /home/opennms/check_url.sh )
down=$(echo "$response" | grep -i down )
count=$(echo "$down" | wc -w)


#logic
Alarm () {

	while IFS= read -r line
	do

		target=$( echo "$line" | awk '{print $2}' )
		string="URL is not responsive $target."
		message=$(echo $string)
		/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/event -n $TARGETDEVICEID1 -d "Ellipse URL"  -p "message $message" -p "resourceId $target" -p "category Ellipse" -x "7"

			echo "$string"


	done < <(printf '%s\n' "$down")






}



#Main

if [ $count != 0 ] ; then

 Alarm

 else
      echo "All urls are up."
	 
 exit;

 fi



