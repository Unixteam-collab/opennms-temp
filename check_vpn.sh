#!/bin/bash

# This script is to be used for checking if a VPN is up
# it functions by having a list of server/port pairs that it can
# test.
#
# Success is defined as any one of the configured server/port pairs
# successfully connecting.
#
# Parameters:
#   1.  VPN ID: an identifier to enable monitoring of multiple VPN's
#   2.  Message to send to zenoss to humanly identify vpn
#   3.  Team to send event to (Networks, Windows, UNIX, Oracle, Ellipse, AXIS)
#   4.  Threshold of number of fails that will trigger an alert


# # Entry from /etc/snmp/snmpd.conf:
# # VPN Monitor test
# ####
# extend vpn_monitor_test /bin/bash /usr/local/bin/check_vpn.sh 1 "VPN to customer is down" COMMS 5


# # snmpwalk -v2c -cgcsapac localhost NET-SNMP-EXTEND-MIB::nsExtendObjects
# NET-SNMP-EXTEND-MIB::nsExtendNumEntries.0 = INTEGER: 1
# NET-SNMP-EXTEND-MIB::nsExtendCommand."vpn_monitor_test" = STRING: /bin/bash
# NET-SNMP-EXTEND-MIB::nsExtendArgs."vpn_monitor_test" = STRING: /usr/local/bin/check_vpn.sh 1 test
# NET-SNMP-EXTEND-MIB::nsExtendInput."vpn_monitor_test" = STRING: 
# NET-SNMP-EXTEND-MIB::nsExtendCacheTime."vpn_monitor_test" = INTEGER: 5
# NET-SNMP-EXTEND-MIB::nsExtendExecType."vpn_monitor_test" = INTEGER: exec(1)
# NET-SNMP-EXTEND-MIB::nsExtendRunType."vpn_monitor_test" = INTEGER: run-on-read(1)
# NET-SNMP-EXTEND-MIB::nsExtendStorage."vpn_monitor_test" = INTEGER: permanent(4)
# NET-SNMP-EXTEND-MIB::nsExtendStatus."vpn_monitor_test" = INTEGER: active(1)
# NET-SNMP-EXTEND-MIB::nsExtendOutput1Line."vpn_monitor_test" = STRING: 1
# NET-SNMP-EXTEND-MIB::nsExtendOutputFull."vpn_monitor_test" = STRING: 1
# test
# 1
# 0
# NET-SNMP-EXTEND-MIB::nsExtendOutNumLines."vpn_monitor_test" = INTEGER: 4
# NET-SNMP-EXTEND-MIB::nsExtendResult."vpn_monitor_test" = INTEGER: 0
# NET-SNMP-EXTEND-MIB::nsExtendOutLine."vpn_monitor_test".1 = STRING: 1
# NET-SNMP-EXTEND-MIB::nsExtendOutLine."vpn_monitor_test".2 = STRING: test
# NET-SNMP-EXTEND-MIB::nsExtendOutLine."vpn_monitor_test".3 = STRING: 1
# NET-SNMP-EXTEND-MIB::nsExtendOutLine."vpn_monitor_test".4 = STRING: 0
# # snmpwalk -v2c -cgcsapac localhost -On NET-SNMP-EXTEND-MIB::nsExtendObjects
# .1.3.6.1.4.1.8072.1.3.2.1.0 = INTEGER: 1
# .1.3.6.1.4.1.8072.1.3.2.2.1.2.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = STRING: /bin/bash
# .1.3.6.1.4.1.8072.1.3.2.2.1.3.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = STRING: /usr/local/bin/check_vpn.sh 1 test
# .1.3.6.1.4.1.8072.1.3.2.2.1.4.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = STRING: 
# .1.3.6.1.4.1.8072.1.3.2.2.1.5.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = INTEGER: 5
# .1.3.6.1.4.1.8072.1.3.2.2.1.6.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = INTEGER: exec(1)
# .1.3.6.1.4.1.8072.1.3.2.2.1.7.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = INTEGER: run-on-read(1)
# .1.3.6.1.4.1.8072.1.3.2.2.1.20.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = INTEGER: permanent(4)
# .1.3.6.1.4.1.8072.1.3.2.2.1.21.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = INTEGER: active(1)
# .1.3.6.1.4.1.8072.1.3.2.3.1.1.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = STRING: 1
# .1.3.6.1.4.1.8072.1.3.2.3.1.2.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = STRING: 1
# test
# 1
# 0
# .1.3.6.1.4.1.8072.1.3.2.3.1.3.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = INTEGER: 4
# .1.3.6.1.4.1.8072.1.3.2.3.1.4.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116 = INTEGER: 0
# .1.3.6.1.4.1.8072.1.3.2.4.1.2.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116.1 = STRING: 1
# .1.3.6.1.4.1.8072.1.3.2.4.1.2.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116.2 = STRING: test
# .1.3.6.1.4.1.8072.1.3.2.4.1.2.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116.3 = STRING: 1
# .1.3.6.1.4.1.8072.1.3.2.4.1.2.16.118.112.110.95.109.111.110.105.116.111.114.95.116.101.115.116.4 = STRING: 0



#
#  History
#
#     4/5/2016 - JDB -  Added code to allow for a threshold of failures

PATH=/bin:/usr/bin

VPNID=$1
MESSAGE=$2
TEAM=$3
if [ $# = 4 ]
then
   THRESHOLD=$4
else
   THRESHOLD=1
fi

MON_LIST=/usr/local/etc/monitor.txt

FAILCOUNTFILE=/var/tmp/vpnmonitor.${VPNID}.failcount

if [ -f $FAILCOUNTFILE ]
then
   FAILCOUNT=$(cat ${FAILCOUNTFILE})
else
  FAILCOUNT=0
fi




FAILED=1

FAILED_IP_LIST=""

while read VPN HOST PORT
do
   if [ "$VPN" = "$VPNID" ]
   then
      #CONN=$(echo | telnet $HOST $PORT 2> /dev/null | grep -c Connected)
      /bin/nc --send-only -w 5 $HOST $PORT < /dev/null > /dev/null 2>&1
      CONN=$?
      if [ $CONN -eq 0 ]
      then 
        FAILED=0
      else
         FAILED_IP_LIST="$FAILED_IP_LIST $HOST:$PORT" 
      fi
   fi

done < $MON_LIST

if [ $FAILED -eq 1 ]
then 
   FAILCOUNT=$(( FAILCOUNT + 1 ))
else
   FAILCOUNT=0
fi

echo $FAILCOUNT > $FAILCOUNTFILE

#if [ $FAILCOUNT -ge $THRESHOLD ]
#then 
#   echo "CRITICAL:VPN is down $MESSAGE Source is CI; Failed connection destinations: $FAILED_IP_LIST | vpn_mon_$VPNID=$FAILCOUNT;;;;"
#else
#   echo "OK:VPN OK | vpn_mon_$VPNID=$FAILCOUNT;;;;"
#   # if fail count is less than 0, then not yet classed as a fail.
#   FAILED=0
#fi

echo $VPNID
echo $MESSAGE \\nFailed test destinations: $FAILED_IP_LIST
echo $THRESHOLD
echo $FAILCOUNT
echo $TEAM

exit $FAILED

