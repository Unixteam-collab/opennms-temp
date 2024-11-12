#!/bin/bash

RESOURCEID=$1
METRICS="CPU Credits Remaining,Cpu Credits Consumed"


METRICS=$(echo "$METRICS"| sed -e 's/ /%20/g')
METRIC_COUNT=$(echo $METRICS| tr \, \  | wc -w)

 
URI=$RESOURCEID'/providers/microsoft.insights/metrics\?api-version=2018-01-01&metricnames='$METRICS'&timespan='$(date -u --date='5 minutes ago' "+%Y-%m-%dT%H:%M:%SZ")'/'$(date -u "+%Y-%m-%dT%H:%M:%SZ")'&interval=PT5M'

#echo URI="$URI"

#echo about to get VM_Size

VM_SIZE=$(curl -m $TIMEOUT -X GET  -H "Authorization: Bearer $ACCESS_TOKEN"  -H "Content-Type: application/json"  https://management.azure.com$RESOURCEID\?api-version=2017-12-01 | jq .properties.hardwareProfile.vmSize | sed -e 's/"//g')
 


CLASS=$(echo $VM_SIZE | cut -d_ -f2 | cut -c-1)
#echo VM_SIZE=$VM_SIZE, CLASS=$CLASS


if [ "$CLASS" == "B" ]
then
  METRIC_DATA="$(curl -m $TIMEOUT -X GET  -H "Authorization: Bearer $ACCESS_TOKEN"  -H "Content-Type: application/json"  "https://management.azure.com$URI" )"
  if [ $? = 0 ]
  then
    for ((COUNT=0;COUNT<$METRIC_COUNT;COUNT++))
    do 
       METRIC=$(echo "$METRIC_DATA" |jq .value[$COUNT].name.localizedValue)
       VALUE=$(echo "$METRIC_DATA" |jq .value[$COUNT].timeseries[].data[].average)
       echo "   <metric type=$METRIC value=\"$VALUE\" />"
    done
  fi
fi
