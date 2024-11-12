#!/bin/bash


USAGE="USAGE: $0 [-n] [-p] [-c] [-t] [-h] <OpenNMS server> <OutageName> <length> <nodename> <package>"

usage ()
{
   echo "$USAGE"
   exit
}

OUTAGE_TYPE=""
ONSUSER=admin
ONSPWD=kntEof3EH6BDgtnPaBNU

while getopts "hnpct" opt; do
    case "${opt}" in
        h)
            echo "$USAGE"
            echo 
            echo " -n suppress all notifications"
            echo " -p suppress Status polling"
            echo " -c suppress Data collection"
            echo " -t suppress Threshold checking"
            echo " -h display this message"
            echo
            echo " <OpenNMS server> - Name of OpenNMS server to raise outage against"
            echo " <OutageName> - Name of outage in OpenNMS"
            echo " <lenght> - Lenght of outage in minutes"
            echo " <nodename> - Nodename in OpenNMS"
            echo " <package> - List of packages to place in outage"
            exit
            ;;
        n)
            OUTAGE_TYPE="$OUTAGE_TYPE notifd"
            ;;
        p)
            OUTAGE_TYPE="$OUTAGE_TYPE pollerd"
            ;;
        c)
            OUTAGE_TYPE="$OUTAGE_TYPE collectd"
            ;;
        t)
            OUTAGE_TYPE="$OUTAGE_TYPE threshd"
            ;;
        *)
            usage
            ;;
    esac
done

if [ "X$OUTAGE_TYPE" == "X" ]
then
   echo "ERROR: no outage type specified"
   usage
fi

shift $((OPTIND-1))

case  "$#" in
    0)
       echo "ERROR: missing OpenNMS Server"
       usage
       ;;
    1)
       echo "ERROR: missing outage name"
       usage
       ;;
    2)
       echo "ERROR: Missing outage length"
       usage
       ;;
    3)
       echo "ERROR: Missing nodename"
       usage
       ;;
    4)
       echo "ERROR: Missing package list"
       usage
       ;;
    *)
        ONS_SERVER="$1"
        OUTAGE_NAME="$2"
        LENGTH="$3"
        NODENAME="$4"
        shift;shift;shift;shift
        while [ $# -gt 0 ]
        do 
           PACKAGE="$PACKAGE $(echo $1 | sed  's/ /%20/g')"
           shift
        done
       ;;
esac


NODE_ID=$(curl -m 30 http://$ONSUSER:$ONSPWD@$ONS_SERVER:8980/opennms/rest/nodes\?limit=0 2> /dev/null | xmllint --format - | grep label | grep node | grep -w "\"$NODENAME\"" | awk -F'id="|" type="' '{ print $2 }' )

# calculate start date based on OpenNMS servers local time.  (to cater for OpenNMS server and this server being in different timezones.  
rdatestring=$( snmpget -v2c -c OpenNMSMon $ONS_SERVER HOST-RESOURCES-MIB::hrSystemDate.0 | gawk '{print $NF}' )

#  if nothing returned, then just use local time
if [ ! "$rdatestring" ] ; then
   OUTAGE_START=$(date "+%d-%b-%Y %H:%M:%S")
else
   # Convert SNMP datetime to unix datetime
   rdate=$( echo $rdatestring | gawk -F',' '{print $1}' )
   rtime=$( echo $rdatestring | gawk -F',' '{print $2}' | gawk -F'.' '{print $1}' )
   cldate=$( echo $rdate | gawk -F'-' '{printf("%4i",$1)}; {printf("%02i",$2)}; {printf("%02i",$3)};' )
   cltime=$( echo $rtime | gawk -F':' '{printf("%02i",$1)}; {printf("%02i",$2)}; {printf(" %02i",$3)};' )
   OUTAGE_START=$( date -d "$cldate $cltime sec" "+%d-%b-%Y %H:%M:%S" )
fi

OUTAGE_END=$(date -d "$OUTAGE_START $LENGTH min" "+%d-%b-%Y %H:%M:%S")

BODY='<?xml version="1.0"?>
<outage name="'$OUTAGE_NAME'" type="specific">
<time begins="'$OUTAGE_START'" ends="'$OUTAGE_END'" />
<node id ="'$NODE_ID'" />
</outage>'

# clean up leftovers of previous instance of this outage
for TYPE in notifd collectd pollerd threshd
do
     curl -m 30 -s -X DELETE "http://$ONSUSER:$ONSPWD@$ONS_SERVER:8980/opennms/rest/sched-outages/$OUTAGE_NAME/$TYPE" > /dev/null 2>&1
done
curl -m 30 -s -X DELETE "http://$ONSUSER:$ONSPWD@$ONS_SERVER:8980/opennms/rest/sched-outages/$OUTAGE_NAME" > /dev/null 2>&1
sleep 5

echo Creating $OUTAGE_NAME schedule
curl -m 30 -s -X POST -H 'Content-type: application/xml' -d "$BODY" "http://$ONSUSER:$ONSPWD@$ONS_SERVER:8980/opennms/rest/sched-outages" 
sleep 5

for TYPE in $OUTAGE_TYPE
do
   if [ $TYPE == 'notifd' ]
   then
      echo linking $OUTAGE_NAME to $TYPE
      curl -m 30 -s -X PUT "http://$ONSUSER:$ONSPWD@$ONS_SERVER:8980/opennms/rest/sched-outages/$OUTAGE_NAME/notifd" 
   else 
      for PKG in $PACKAGE
      do
         echo linking $OUTAGE_NAME to $TYPE/$PKG
         curl -m 30 -s -X PUT "http://$ONSUSER:$ONSPWD@$ONS_SERVER:8980/opennms/rest/sched-outages/$OUTAGE_NAME/$TYPE/$PKG"
      done
   fi
done
