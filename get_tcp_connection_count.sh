#!/bin/bash


# run from /opt/opennms/scripts/run_monitor.sh
# Variables that are defined in run_monitor.sh:
# ONSUSER ONSPWD NODEID NODENAME NODEIP SERVICENAME HOME VAR ETC COMMUNITY SNMPHOST

# to test: /opt/opennms/scripts/run_monitor.sh  <nodeid> <nodename> <ipaddr> <svcname> '/opt/opennms/scripts/get_tcp_connection_count.sh 443 established'
# eg:
# /opt/opennms/scripts/run_monitor.sh 385 aue-s-opennms01.gms.mincom.com 10.2.0.9 Test '/opt/opennms/scripts/get_tcp_connection_count.sh 443 established'

if [[ "X$COMMUNITY" == "X" ]]
then
   echo snmp community not found exiting
   exit 0
fi

PORT=$1
STATE=$2

DEFAULT_THRESHOLD=250
CONF_DIR=$ETC/tcp_connection_mon
THRESH_FILE=$CONF_DIR/tcp_connections_$NODENAME.conf
TMP_METRIC_FILE=$VAR/metrics/.tcp_connections_$NODEIP.xml.$$
METRIC_FILE=$VAR/metrics/tcp_connections_$NODEIP.xml

if [ ! -d $CONF_DIR ]
then
   mkdir -p $CONF_DIR
fi

if [ ! -f $THRESH_FILE ]
then
   echo $PORT $STATE $DEFAULT_THRESHOLD >> $THRESH_FILE
fi

THRESHOLD=$(cat $THRESH_FILE | while read P S T
do
   if [ \( $P = $PORT \) -a \( $S = $STATE \) ]
   then
      echo $T
   else
      echo $DEFAULT_THRESHOLD
      echo $PORT $STATE $DEFAULT_THRESHOLD >> $THRESH_FILE
   fi
done)

CURRENT=$(snmpwalk -v2c -On -c $COMMUNITY $SNMPHOST 1.3.6.1.2.1.6.13.1.1.$NODEIP.$PORT |  grep $STATE | wc -l)
echo "<node id=\"$NODEID\">" > $TMP_METRIC_FILE
echo "   <interface ip=\"$NODEIP\">" >> $TMP_METRIC_FILE
echo "      <port port=\"$PORT\" state=\"$STATE\" count=\"$CURRENT\" threshold=\"$THRESHOLD\"/>" >> $TMP_METRIC_FILE
echo "   </interface>" >> $TMP_METRIC_FILE
echo "</node>" >> $TMP_METRIC_FILE

mv $TMP_METRIC_FILE $METRIC_FILE

echo Connection count for $STATE connections to port $PORT is $CURRENT.  Threshold $THRESHOLD

exit 0
