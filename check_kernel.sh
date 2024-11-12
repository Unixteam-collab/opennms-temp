#!/bin/bash

# run from /opt/opennms/scripts/run_monitor.sh
# Variables that are defined in run_monitor.sh:
# ONSUSER ONSPWD NODEID NODENAME NODEIP SERVICENAME HOME VAR ETC COMMUNITY SNMPHOST
# v3 add new variables ONSUSER ONSPWD NODEID NODENAME NODEIP SERVICENAME HOME VAR ETC SNMPHOST SNMPVERSION SECURITYNAME AUTHPROTOCOL AUTHPASSPHRASE PRIVPROTOCOL PRIVPASSPHRASE


if [ "$SNMPVERSION" == "v2c" ]
        then
		if [[ "X$COMMUNITY" == "X" ]]
			then
			   echo snmp community not found exiting
			   exit 0
		fi
fi

if [ "$SNMPVERSION" == "v2c" ]
        then
                echo "snmpget -t10 -$SNMPVERSION -Ov -Oq -c  $COMMUNITY $SNMPHOST  .1.3.6.1.2.1.1.1.0 | awk '{ print $3}' " 1>&2
                SRUNNING=$(snmpget -t10 -$SNMPVERSION -Ov -Oq -c  $COMMUNITY $SNMPHOST  .1.3.6.1.2.1.1.1.0 | awk '{ print $3}' | cut -d\" -f2 )
        else
                echo "snmpget -t10 -$SNMPVERSION -Ov -Oq -l authPriv -u $SECURITYNAME -a $AUTHPROTOCOL  -A $AUTHPASSPHRASE -x $PRIVPROTOCOL -X $PRIVPASSPHRASE $SNMPHOST  .1.3.6.1.2.1.1.1.0 | awk '{ print $3}' " 1>&2
                SRUNNING=$(snmpget -t10 -$SNMPVERSION -Ov -Oq -l authPriv -u $SECURITYNAME -a $AUTHPROTOCOL  -A $AUTHPASSPHRASE -x $PRIVPROTOCOL -X $PRIVPASSPHRASE $SNMPHOST  .1.3.6.1.2.1.1.1.0 | awk '{ print $3}' | cut -d\" -f2 )

fi

RUNNING=${SRUNNING%.*}

if [[ "$SRUNNING" == *uek* ]]
then
   UEK_SWITCH=""
else
   UEK_SWITCH="-v"
fi

#echo "snmpwalk -t10 -v2c -Ov -Oq -c $COMMUNITY $SNMPHOST .1.3.6.1.2.1.25.6.3.1.2 | grep kernel | grep -v firmware | grep -v tools| grep -v headers | grep $UEK_SWITCH uek | sort -V | tail -1" 1>&2
if [ "$SNMPVERSION" == "v2c" ]
        then
                echo "snmpwalk -t10 -$SNMPVERSION -Ov -Oq -c $COMMUNITY $SNMPHOST .1.3.6.1.2.1.25.6.3.1.2 | grep kernel | grep -E -v 'firmware|tools|headers|dracut|plugin|addon' | grep $UEK_SWITCH uek| cut -d\" -f2 |sort -V| tail -1" 1>&2
                INSTALLED=$(snmpwalk -t10 -$SNMPVERSION -Ov -Oq -c $COMMUNITY $SNMPHOST .1.3.6.1.2.1.25.6.3.1.2 | grep kernel | grep -E -v 'firmware|tools|headers|dracut|plugin|addon' | grep $UEK_SWITCH uek | cut -d\" -f2 |sort -V| tail -1)

        else
                echo "snmpwalk -t10 -$SNMPVERSION -Ov -Oq -l authPriv -u $SECURITYNAME -a $AUTHPROTOCOL  -A $AUTHPASSPHRASE -x $PRIVPROTOCOL -X $PRIVPASSPHRASE $SNMPHOST .1.3.6.1.2.1.25.6.3.1.2 | grep kernel | grep -E -v 'firmware|tools|headers|dracut|plugin|addon' | grep $UEK_SWITCH uek| cut -d\" -f2 |sort -V| tail -1" 1>&2
                INSTALLED=$(snmpwalk -t10 -$SNMPVERSION -Ov -Oq -l authPriv -u $SECURITYNAME -a $AUTHPROTOCOL  -A $AUTHPASSPHRASE -x $PRIVPROTOCOL -X $PRIVPASSPHRASE $SNMPHOST .1.3.6.1.2.1.25.6.3.1.2 | grep kernel | grep -E -v 'firmware|tools|headers|dracut|plugin|addon' | grep $UEK_SWITCH uek | cut -d\" -f2 |sort -V| tail -1)
fi


echo
echo Installed kernel: $INSTALLED
echo Running kernel: $RUNNING

if [[ "X$INSTALLED" == "X" || "X$RUNNING" == "X" ]]
then
   echo Missing value for INSTALLED OR RUNNING.  Please email JohnD so he can check code.
   exit 0
fi

if [[ $INSTALLED == *"$RUNNING"* ]]
then
   echo reboot not required
   exit 0
else
   echo reboot required
   exit 1
fi
