#!/bin/bash

CATEGORY="Operating System"
SEVERITY=4

usage ()
{
   echo 'test_event.sh [-p priority] [-q "support team"] [hostname]'
   echo 'Support Team: UNIX, MST, COMMS, DBA, AXIS       Default Unix'
   echo 'priority: 4-7  (warning - critical)             Default 4'
   exit
}

while getopts "p:q:" opt; do
    case "${opt}" in
        p)
            SEVERITY=${OPTARG}
            ;;
        q)
            CATEGORY=${OPTARG}
            ;;
        :)
            echo "Option: -$OPTARG requires an argument." >&2
            usage
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

case  "$#" in
    0)
       targetDevice=`hostname`
       ;;
    1)
       targetDevice=$1
       ;;
    *)
       usage
       ;;
esac

re='^[0-9]+$'
if ! [[ $targetDevice =~ $re ]]
then 
  targetDeviceID=$(/opt/opennms/scripts/getNodeID.sh $targetDevice)
  if [ $? = 1 ]
  then
    echo Node Not Found
    exit 1
  fi
else
  targetDeviceID=$targetDevice
fi
# echo targetDeviceID=$targetDeviceID

#  /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/testevent localhost --parm '_foreignSource Servers' --parm "_foreignId $targetDevice" -d "ABBCS Test event" -p "description ABBCS Test Event"  
/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/testevent localhost -n $targetDeviceID -d "ABBCS Test event" -p "description ABBCS Test Event"  --severity $SEVERITY --parm "category $CATEGORY"

