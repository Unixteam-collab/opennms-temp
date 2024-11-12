#!/bin/bash

# poller service to define:
#
#   <service name="SERVICE_NAME" interval="300000" user-defined="false" status="on">
#      <parameter key="script" value="/opt/opennms/scripts/run_monitor.sh"/>
#      <parameter key="retry" value="0"/>
#      <parameter key="args" value="${nodeid} ${nodelabel} ${ipaddr} ${svcname} 'commandline'"/>
#      <parameter key="timeout" value="240000">
#      <parameter key="rrd-base-name" value="SERVICE_NAME"/>
#      <parameter key="rrd-repository" value="/opt/opennms/share/rrd/response"/>
#      <parameter key="ds-name" value="example-monitoring/>
#   </service>

NODEID=$1
shift
NODENAME=$1
shift
NODEIP=$1
shift
SERVICENAME=$1
shift
COMMAND="$*"

HOME=/home/opennms
VAR=$HOME/var
LOGDIR=$HOME/logs/$NODENAME
ETC=$HOME/etc
LOG="${LOGDIR}/run_monitor_${SERVICENAME}_${NODENAME}.log"

. /opt/opennms/.ABBCS_Config_defaults/.opennms.creds

if [ ! -d $LOGDIR ]
then
   mkdir -p $LOGDIR
   mv $LOGDIR/../run_monitor*${NODENAME}* $LOGDIR
fi

echo Start: $(date) >> $LOG
echo $0 "$*" >> $LOG
echo "NODEID=$NODEID" >> $LOG
echo "NODENAME=$NODENAME" >> $LOG
echo "NODEIP=$NODEIP" >> $LOG
echo "SERVICENAME=$SERVICENAME" >> $LOG
echo "COMMAND=$COMMAND" >> $LOG

SNMPDATA=$(curl -m 60 http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/snmpConfig/$NODEIP 2>>$LOG | tee -a $LOG )
CURLRESP=$?

if [ $CURLRESP != 0 ]
then
   echo unable to communicate with OpenNMS.  Exiting >> $LOG
   exit 0
fi

#added by cm6489
SNMPVERSION=$(echo "$SNMPDATA" | xmllint --xpath "string(/snmp-info/version)" -)

if [ "$SNMPVERSION" == "v2c" ]
then
	COMMUNITY=$(echo "$SNMPDATA" | xmllint --xpath "string(/snmp-info/community)" -)
	PROXYHOST=$(echo "$SNMPDATA" | xmllint --xpath "string(/snmp-info/proxyHost)" -)


	if [ "X$PROXYHOST" == "X" ]
	then
	   SNMPHOST=$NODEIP
	else
	   SNMPHOST=$PROXYHOST
	fi 

	export ONSUSER ONSPWD NODEID NODENAME NODEIP SERVICENAME HOME VAR ETC COMMUNITY SNMPHOST SNMPVERSION

else
	SECURITYNAME=$(echo "$SNMPDATA" | xmllint --xpath "string(/snmp-info/securityName)" -)
	AUTHPROTOCOL=$(echo "$SNMPDATA" | xmllint --xpath "string(/snmp-info/authProtocol)" -)
	AUTHPASSPHRASE=$(echo "$SNMPDATA" | xmllint --xpath "string(/snmp-info/authPassPhrase)" -)
	PRIVPROTOCOL=$(echo "$SNMPDATA" | xmllint --xpath "string(/snmp-info/privProtocol)" -)
	PRIVPASSPHRASE=$(echo "$SNMPDATA" | xmllint --xpath "string(/snmp-info/privPassPhrase)" -)
	PROXYHOST=$(echo "$SNMPDATA" | xmllint --xpath "string(/snmp-info/proxyHost)" -)

        if [ "X$PROXYHOST" == "X" ]
        then
           SNMPHOST=$NODEIP
        else
           SNMPHOST=$PROXYHOST
        fi
	export ONSUSER ONSPWD NODEID NODENAME NODEIP SERVICENAME HOME VAR ETC SNMPHOST SNMPVERSION SECURITYNAME AUTHPROTOCOL AUTHPASSPHRASE PRIVPROTOCOL PRIVPASSPHRASE
fi


#env >> $LOG


echo about to run $COMMAND >> $LOG

OUTPUT=$($COMMAND 2>>$LOG)
RETVAL=$?

echo command completed >> $LOG

echo "$OUTPUT" >> $LOG
echo Return Value = $RETVAL >> $LOG

echo End: $(date) >> $LOG

echo "$OUTPUT"
exit $RETVAL
