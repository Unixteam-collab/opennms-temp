#!/bin/bash
#
#***************URL monitoring by Sadish Nambiar - v1******************
# 11/06/2020
#***History***
# This script is written to cope monitoring for Appliance structure for now. 
# Does not support Azure client, also believe there is already HTTP monitoring for it.


TARGETDEVICEID1=$1       # Numeric ID of monitored DB - from OpenNMS GUI
TARGETDEVICEID2=$2       # Numeric ID of monitored DB - from OpenNMS GUI
TARGETDEVICEID3=$3       # Numeric ID of monitored DB - from OpenNMS GUI
TARGETDEVICEID4=$4       # Numeric ID of monitored DB - from OpenNMS GUI
TARGETDEVICEID5=$5       # Numeric ID of monitored DB - from OpenNMS GUI
applianceHOST=$6         # Appliance hostname or IP

response=$(ssh -q opennms@"$applianceHOST" /home/opennms/check_url.sh )
down=$(echo "$response" | grep -i down )
count=$(echo "$down" | wc -l)



# function to filter

Filter () {

ell1=$( echo "$down" | grep -i ellipse01 |  awk '{print $2}' )
ell2=$( echo "$down" | grep -i ellipse02 |  awk '{print $2}' )
ell3=$( echo "$down" | grep -i ellipse03 |  awk '{print $2}' )
ews1=$( echo "$down" | grep -i ews01 |  awk '{print $2}' )
vip1=$( echo "$down" | grep -i vip01 |  awk '{print $2}' )


#Criteria check
if [ !  -z "$ell1" ] ; then

string="Ellipse01 Online is not responsive $ell1."
message=$(echo $string)
/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/event -n $TARGETDEVICEID1 -d "Ellipse URL"  -p "message $message" -p "resourceId URL_Test" -p "category Ellipse" -x "7"


fi



if [ ! -z "$ell2" ] ; then

string="Ellipse02 Online is not responsive $ell2."
message=$(echo $string)
/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/event -n $TARGETDEVICEID2 -d "Ellipse URL"  -p "message $message" -p "resourceId URL_Test" -p "category Ellipse" -x "7"


fi


if [ ! -z "$ell3" ] ; then

string="Ellipse03 Online is not responsive $ell3."
message=$(echo $string)
/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/event -n $TARGETDEVICEID3 -d "Ellipse URL"  -p "message $message" -p "resourceId URL_Test" -p "category Ellipse" -x "7"

fi


if [ ! -z "$ews1" ] ; then

string="Ews01 Online is not responsive $ews1."
message=$(echo $string)
/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/event -n $TARGETDEVICEID4 -d "Ellipse URL"  -p "message $message" -p "resourceId URL_Test" -p "category Ellipse" -x "7"


fi


if [ ! -z "$vip1" ] ; then

string="VIP Online is not responsive $vip1."
message=$(echo $string)
/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/event -n $TARGETDEVICEID5 -d "Ellipse URL"  -p "message $message" -p "resourceId URL_Test" -p "category Ellipse" -x "7"



fi

}

#Main

if [ $count != 0 ] ; then

 Filter

 else

 exit;

 fi



