#!/bin/bash

SNMP_CONFIG_DIR=/etc/snmp/config.d
SNMP_LOCAL_CONFIG=/etc/snmp/snmpd.local.conf
LOCAL_CONF=$SNMP_CONFIG_DIR/local.conf

APP_CONFIG=$SNMP_CONFIG_DIR/Appliance.conf


if [ ! -d $SNMP_CONFIG_DIR ]
then
   mkdir $SNMP_CONFIG_DIR
fi


echo 'extend appliance /bin/bash /home/opennms/get_vmlist' > $APP_CONFIG


APPL=$(hostname | awk -F. '{print $1}'| awk -F"-s-" '{ print $1$2}')

su - oneadmin -c "onevm list" | grep ventyx | awk '{ print $4 }' | while read GUEST
do
   echo $GUEST 
   DEV=$(echo $GUEST | awk -F . '{print $1$2"'$APPL'"}')
   # Truncate $DEV due to internal snmpd limitations
   TDEV=${DEV:0:30}
   FILE=$SNMP_CONFIG_DIR/$DEV.conf

   cat > $FILE <<!EOF
com2sec -Cn $TDEV notConfigUser default cmty_$DEV
access  notConfigGroup $TDEV    any       noauth    exact  systemview none   none
proxy -Cn $TDEV -v 2c -c public $GUEST .1.3
!EOF

done

echo "includeDir $SNMP_CONFIG_DIR" > $SNMP_LOCAL_CONFIG

cat > $LOCAL_CONF << !EOF
ignoreDisk /dev/shm
ignoreDisk /run
ignoreDisk /sys/fs/cgroup
ignoreDisk /appliance/data/repo/yum/ol7.6
ignoreDisk /dev/loop0
includeAllDisks 10%
skipNFSInHostResources 1
!EOF

systemctl restart snmpd

useradd -c "OpenNMS monitoring user" -m -d /home/opennms opennms
#echo
#echo add the following 2 lines to /appliance/data/conf/puppet/modules/current/level3/core/templates/etc/sudoers.erb
#echo '## Read drop-in files from /etc/sudoers.d (the # here does not mean a comment)'
#echo '#includedir /etc/sudoers.d'
#echo

PUPPET_UPDATE=0
for i in /appliance/data/conf/puppet/modules/*/level3/core/files/etc/snmp/snmpd.conf
do
   if [ ! "$(grep proxy $i)" ]
   then
     PUPPET_UPDATE=1
     echo >> $i
     echo "proxy -v 2c -c public localhost:1610 .1.3.6.1.4.1.42" >> $i
   fi
done

for i in /appliance/data/conf/puppet/modules/*/level3/core/templates/etc/sudoers.erb
do
   if [ ! "$(grep  '#includedir /etc/sudoers.d' $i)" ]
   then
     PUPPET_UPDATE=1
     echo >> $i
     echo '## Read drop-in files from /etc/sudoers.d (the # here does not mean a comment)' >> $i
     echo '#includedir /etc/sudoers.d' >> $i
   fi
done

if [ $PUPPET_UPDATE = '1' ]
then
   puppet agent --test
fi

echo '#!/bin/bash
for i in $(sudo /usr/local/bin/onsvmlist | grep ventyx | awk '\''{ print $4 }'\'')
do
   echo -n $i " "
   nslookup $i | tail -2 | grep Address | awk '\''{ print $2 }'\''

done
' > /home/opennms/get_vmlist 

chown opennms /home/opennms/get_vmlist
chmod 755 /home/opennms/get_vmlist

echo 'opennms    ALL=NOPASSWD: /usr/local/bin/onsvmlist' > /etc/sudoers.d/opennms

echo '#!/bin/bash
PATH=/bin:/usr/bin:/Appliance/cloud/one/bin 
export PATH 
unset IFS 
ONEVM=$(which onevm) 
/bin/su - oneadmin -c "$ONEVM list"' > /usr/local/bin/onsvmlist

chown root:root /usr/local/bin/onsvmlist
chmod 700 /usr/local/bin/onsvmlist

echo '#!/usr/bin/bash

dt=$(date '+%Y%d%m%H%M%S')

HOSTNAME=$(hostname)

if [[ $HOSTNAME == "vip"* ]]
then
   CONFIG=/etc/jboss-as/VIP.conf
else
   CONFIG=/etc/jboss-as/ellipse.conf
fi

if [ ! -f ${CONFIG}.orig ]; then
	echo "Original puppet ellipse.conf not exists"
	cp $CONFIG ${CONFIG}.orig
fi
cp $CONFIG ${CONFIG}.${dt}

if [ -f "$CONFIG" -a -f "${CONFIG}.${dt}" ]; then
	echo "file copy successful!!"
else
	echo "file copy failed!!"
	exit 1
fi

CNT=`grep "Dcom.sun.management.snmp.port=1610" $CONFIG |wc -l`
if [ $CNT == 0 ]; then
	JBOSS_LOG_JAR=`find /opt/ellipse -name jboss-logmanager\*`
	echo "" >> $CONFIG
	echo "###Added by ABB for Monitoring" >> $CONFIG
	echo "JAVA_OPTS=\"\$JAVA_OPTS -Dcom.sun.management.snmp.port=1610\"" >> $CONFIG
	echo "JAVA_OPTS=\"\$JAVA_OPTS -Dcom.sun.management.snmp.interface=127.0.0.1\"" >> $CONFIG
	echo "JAVA_OPTS=\"\$JAVA_OPTS -Dcom.sun.management.snmp.acl=false\"" >> $CONFIG
	echo "JAVA_OPTS=\"\$JAVA_OPTS -Djboss.modules.system.pkgs=org.jboss.byteman,org.jboss.logmanager -Djava.util.logging.manager=org.jboss.logmanager.LogManager -Xbootclasspath\/p:${JBOSS_LOG_JAR}\"" >> $CONFIG
	echo "export JAVA_OPTS" >> $CONFIG
        echo "Please restart ellipse"
else
	echo "Please check your $CONFIG copy!!"
fi
 
#service ellipse stop
#service ellipse start
' > /appliance/data/dist/abb_jboss_monitoring_update.sh

chmod 700 /appliance/data/dist/abb_jboss_monitoring_update.sh


