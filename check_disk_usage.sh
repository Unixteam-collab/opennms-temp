#!/bin/bash
# Variables that are defined in run_monitor.sh:
# if snmp is version v2c the variable will be  
#ONSUSER ONSPWD NODEID NODENAME NODEIP SERVICENAME HOME VAR ETC COMMUNITY SNMPHOST
# if snmp is version v3 the varialbe will be 
#ONSUSER ONSPWD NODEID NODENAME NODEIP SERVICENAME HOME VAR ETC SNMPHOST SECURITYNAME AUTHPROTOCOL AUTHPASSPHRASE PRIVPROTOCOL PRIVPASSPHRASE

echo "Variable ONSUSER : $ONSUSER"

CONFIGDIR=$ETC/FSMon
STATDIR=$VAR/metrics/FSMon

if [ ! -d $CONFIGDIR ]
then
   mkdir -p $CONFIGDIR
fi

if [ ! -d $STATDIR ]
then
   mkdir -p $STATDIR
fi

# SNMP OID

OID=.1.3.6.1.2.1.25.2.3.1.
OINDEX=${OID}1

#DEFAULTS
DEF_P4=80
DEF_P3=85
DEF_P2=90
DEF_P1=95
DEF_NOTIFY=UNIX

# Default for JBoss server root filesystem
#   (Requirement due to space requirements for java heap dump needing 40% free space in root filesystem)
#JDEF_P4=60
#JDEF_P3=70
#JDEF_P2=75
#JDEF_P1=80
JDEF_P4=$DEF_P4
JDEF_P3=$DEF_P3
JDEF_P2=$DEF_P2
JDEF_P1=$DEF_P1
JDEF_NOTIFY=APPS


echo Processing $NODENAME

if [ "X$SNMPHOST" == "X" ]
then
   echo can\'t find IP address for snmpwalk -  Skipping
   exit 1
else
   echo Got SNMPHOST: $SNMPHOST

   THRESHOLD_FILE="$CONFIGDIR/$NODENAME.conf"


   STATFILE=$STATDIR/${NODEIP}.xml
   STATFILETMP=$STATDIR/${NODEIP}.xml.tmp
   DATFILE=$STATDIR/${NODENAME}.dat
   DATFILETMP=$STATDIR/${NODENAME}.dat.tmp

   touch $DATFILETMP
# following wmic command gets Windows FS info via wmi 
#wmic -U DOM/USER%PASSWORD //NODE "Select Name,FreeSpace,Size,VolumeName,VolumeSerialNumber  from Win32_LogicalDisk where MediaType = '12'"

#Logic needs to be:
#   if node has Microsoft category
#     try wmic
#     if wmic succeeds then build useage array from wmic output
#   if usage array not built then build usage array from snmp
#   build xml from usage array
#
#  Alternatively, need code to determine wmi or snmp, then call separate functions for different processing.

if [ "$SNMPVERSION" == "v2c" ]
	then
   		INDEX_KEYS=$(snmpwalk -$SNMPVERSION -Ov -OQ -t1 -r1 -c $COMMUNITY $SNMPHOST $OINDEX)
	else
		INDEX_KEYS=$(snmpwalk -$SNMPVERSION -Ov -OQ -t1 -r1 -l authPriv -u $SECURITYNAME -a $AUTHPROTOCOL  -A $AUTHPASSPHRASE -x $PRIVPROTOCOL -X $PRIVPASSPHRASE $SNMPHOST $OINDEX)
fi

   if [ $? == 0 ]
   then 
      echo SNMP response ok, processing.
   
      if [ ! -f $THRESHOLD_FILE ]
      then
         cat >> $THRESHOLD_FILE <<!EOF
#
# This file contains the alerting thresholds for filesystems for $SERVER
# columns:
#     P4 threshold
#     P3 threshold
#     P2 threshold
#     P1 threshold
#     Team to notify (One of UNIX,MST,APPS,DBA,COMMS)
#     name of filesystem (do not edit this value as it is generated from SNMP and used for lookup)
#
!EOF

         chmod g+w $THRESHOLD_FILE

      fi

   
      echo '<server id="'$NODEID'">' > $STATFILETMP

      for KEY in $INDEX_KEYS
      do

        if [ "$SNMPVERSION" == "v2c" ]
	then
	 	FSINFO="$(snmpget -$SNMPVERSION -IS $OID -Is $KEY -Ov -Oq -c $COMMUNITY $SNMPHOST 1 2 3 4 5 6)"
        else
	 	FSINFO="$(snmpget -$SNMPVERSION -IS $OID -Is $KEY -Ov -Oq -l authPriv -u $SECURITYNAME -a $AUTHPROTOCOL -A $AUTHPASSPHRASE -x $PRIVPROTOCOL -X $PRIVPASSPHRASE $SNMPHOST 1 2 3 4 5 6)"
	fi

	if [[ $FSINFO == *"No Such Instance currently exists at this OID"* ]]
         then
            echo not all OID\'s populated on this run, skipping
            echo "$FSINFO"
         else

            readarray -t FSARRAY <<< "$FSINFO"

            # array index
            #0 OINDEX=.1.3.6.1.2.1.25.2.3.1.1
            #1 OTYPE=.1.3.6.1.2.1.25.2.3.1.2
            #2 ODESC=.1.3.6.1.2.1.25.2.3.1.3
            #3 OUNITS=.1.3.6.1.2.1.25.2.3.1.4
            #4 OSIZE=.1.3.6.1.2.1.25.2.3.1.5
            #5 OUSED=.1.3.6.1.2.1.25.2.3.1.6
            TYPE="${FSARRAY[1]}"
            FS="${FSARRAY[2]}"
            SIZE="${FSARRAY[4]}"
            USED="${FSARRAY[5]}"
            PCT_USED=$(echo "scale=4; ($USED/$SIZE)*100" | bc)

            echo Processing filesystem $FS
            if [ "$TYPE" == "HOST-RESOURCES-TYPES::hrStorageFixedDisk" ]
            then
                case $FS in
                   /run*|/dev/shm*|/sys/fs/cgroup|/kvm/guests/*|/var/lib/docker/containers/* )
                      ;;
                   *)
                      if [ $(grep -v '^#' $THRESHOLD_FILE | grep -c " $(echo "$FS" | sed -e 's/\\/\\\\/g')\$" ) == 0 ]
                      then
                         DEF_NOTIFY=$(/opt/opennms/scripts/getCategories.sh $NODENAME UNIX)
                         case "$DEF_NOTIFY" in
                            Window)
                                DEF_NOTIFY=MST
                                ;;
                            Network)
                                DEF_NOTIFY=COMMS
                                ;;
                            *)
                                DEF_NOTIFY=UNIX
                          esac
                          echo curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/categories/Jboss7/nodes/$NODEID 
                          JBOSS_CHECK="$(curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/categories/Jboss7/nodes/$NODEID 2>/dev/null)"
                          echo JBOSS_CHECK=$JBOSS_CHECK
                          echo FS=$FS
                          if [[ "$JBOSS_CHECK" == "Can't find category Jboss7 for node"* || "$FS" != "/" ]]
                          then
                             echo no jboss
                             echo $DEF_P4 $DEF_P3 $DEF_P2 $DEF_P1 $DEF_NOTIFY "$FS" >> $THRESHOLD_FILE
                          else
                             echo jboss and root
                             echo $JDEF_P4 $JDEF_P3 $JDEF_P2 $JDEF_P1 $JDEF_NOTIFY "$FS" >> $THRESHOLD_FILE
                          fi
                      fi
               
                      read P4 P3 P2 P1 NOTIFY xFS<<< $( grep -v '^#' $THRESHOLD_FILE| grep " $(echo "$FS" | sed -e 's/\\/\\\\/g')\$" )

   cat >> $STATFILETMP <<!EOF
   <filesystem fs_mountpoint="$FS" fs_size="$SIZE" fs_used="$USED" fs_pctused="$PCT_USED" fs_notify="$NOTIFY">
      <thresholds P1="$P1" P2="$P2" P3="$P3" P4="$P4" />
   </filesystem>
!EOF
                      echo "$NODEID $NODEIP $NODENAME $SIZE $USED $PCT_USED $NOTIFY $FS"  >> $DATFILETMP
                      ;;
                esac
            fi
         fi

      done

      echo '</server>' >> $STATFILETMP

      mv $DATFILETMP $DATFILE
      mv $STATFILETMP $STATFILE
   else
      echo no SNMP response.  Skipping.
      #rm -f $STATFILE
      exit 0
   fi 
fi
exit 0   
