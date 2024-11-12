#!/bin/sh
#
# calculate the openfiles for the main Java process, total appliance userid  and the total system used
#
# display maximum file open per process cat /proc/PID/limits | grep "Max open files"
#

#  USAGE: /usr/local/bin/Open_Files.sh <username> <SearchString> 
#
#  Place this script in /usr/local/bin 
#  create /etc/snmp/config.d/OpenFiles.conf containing:
#
#  extend OpenFiles /bin/bash /usr/local/bin/Open_Files.sh appliance Ellprod8854
#
#  output:
#    Openfiles for process
#    Openfiles fo
#
#  snmp OID for use in OpenNMS:
#    .1.3.6.1.4.1.8072.1.3.2.4.1.2.9.79.112.101.110.70.105.108.101.115
#
# ABB 12-04-2019 mp - initial version
# ABB 12-04-2019 jb - modified to run from snmp to be ingested by OpenNMS
#

USER=$1
SEARCHSTRING="$2"


JPID=$(ps -ef | grep -v grep | grep -v $0 | grep "$SEARCHSTRING" | awk '{print $2}')
if [ $? -ne 0 ]
then
	JTOTAL=0
	JJTOTAL=0
else
	JTOTAL=$(ls -l /proc/${JPID}/fd/* | wc -l)
	JJTOTAL=$(lsof -u $USER | wc -l)
fi

STOTAL=$(cat /proc/sys/fs/file-nr | awk '{ print $1}')
ULIMIT=$(cat /proc/$JPID/limits | grep "open files" | awk '{print $3}')

date 
echo $USER
echo $SEARCHSTRING
echo $JPID
echo $JTOTAL 
echo $JJTOTAL 
echo $STOTAL

