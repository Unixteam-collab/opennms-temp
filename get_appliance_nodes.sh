#!/bin/bash

APPLIANCE=$1

#SNMP_CHECK=$(snmpget -v2c -cpublic $APPLIANCE -Oqv .1.3.6.1.4.1.8072.1.3.2.2.1.3.9.97.112.112.108.105.97.110.99.101 2> /dev/null)
SNMP_CHECK=$(snmpget -v2c -cpublic $APPLIANCE -Oqv NET-SNMP-EXTEND-MIB::nsExtendArgs.\"appliance\" 2> /dev/null)


if [[ "$SNMP_CHECK" = "/home/opennms/get_vmlist" ]]
then
#   snmpget -v2c -cpublic $APPLIANCE -Oqv .1.3.6.1.4.1.8072.1.3.2.3.1.2.9.97.112.112.108.105.97.110.99.101 2> /dev/null
   snmpget -v2c -cpublic $APPLIANCE -Oqv NET-SNMP-EXTEND-MIB:nsExtendOutputFull.\"appliance\" 2> /dev/null
else
   ssh -q $APPLIANCE /home/opennms/get_vmlist
fi

