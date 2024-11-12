#!/bin/bash

#
#  Program: extract_customisations.sh
#
#  Description:  Extract customisations ready for deployment
#
#  Parameters:   rundis  -  optional.  Including this parameter will trigger execution of "install -dis"
#                           on destination OpenNMS servers.  There are some situations when configuration
#                           changes require execution of "install -dis".
#
#                           Situations known to require "install -dis"
#                              - Opennms Version upgrade - This will automatically trigger execution of "install -dis"
#                              - enable HTTPS interface 
#
#  NOTE: when this script is run by "install_customisations.sh", scheduled outages defined on the current opennms server
#        are cleaned up prior to running this script.  When run manually, links for scheduled outages are exported, and
#        incorrectly carried across to opennms servers that obtain their configuration from this one.
#
#        Under normal operation, aue-s-opennms01 should only ever have OpenNMSConfigUpdate scheduled outage defined linked
#        to notifications.
#
#  Side effects: OpenNMS related packages will be yum version locked after running this script (see ons_version.sh)
#     
#
#  History:                  Initial revision
#           07-Jul-2017  JDB Added code to enable triggering of execution of "install -dis"
#           25-Sep-2017  JDB Added opennms-datasources.xml - config file changed by ONS 20.1 update
#           16-Oct-2017  JDB Added Postgresql config files to enable monitoring of OpenNMS postgresql datatabase
#           06-Dec-2017  JDB Added code to save localized customisations to assist rebuild of opennms server
#           05-Jan-2018  JDB Added backup of RRD data saved for Foreign Source defined nodes
#           23-Feb-2018  JDB Added switch to tar file to ignore read errors due to Local customisations file list
#                            containing reference to files that don't exist on every opennms server.
#           07-Mar-2018  AK  Updates added for openNMS 21.0.4 update
#           20-Mar-2018  JDB Added OpenNMS version to filename containing customisations
#           03-Apr-2018  JDB Added MSSQL jdbc driver (V6.4 for java 8)
#           23-Apr-2018  JDB Updates added for OpenNMS 21.1.0 update
#           02-May-2018  JDB Modified to backup RRD via real location of data rather than symlinked path
#           28-May-2018  JDB mode 600 for backup files
#           30-May-2018  JDB added MSSQL ODBC repo
#           22-Aug-2018  JDB added MSSQL Scripts directory
#           26-Oct-2018  JDB added code to set version lock
#           15-Nov-2018  JDB Added ksc-performance-reports.xml to local changes to backup.
#           19-Nov-2018  JDB Added JVM-MANAGEMENT-MIB
#           05-Dec-2018  JDB Added opennms.pollerd.events.xml and /etc/init.d/opennms_customisations
#           11-Jun-2019  JDB Added OpsGenie Ticketing config files
#           08-Jul-2019  JDB Added Website and OpenNMSServers Foreign Source definitions
#           02-Aug-2019  JDB Added CPAN MyConfig.pm file
#           04-Sep-2019  JDB Added opennms-datasources.xml default setup, and customisations backup
#           19-Sep-2019  JDB Added eventd-configuration.xml
#           20-Sep-2019  JDB Added wmi-config.xml to backup local changes.
#           24-Oct-2019  JDB Added rpm gpg keys 
#           11-Nov-2019  JDB Added web publishing of configuration
#           09-Aug-2022  JDB Added backup of the requisitions
#           21-Jun-2024  JDB Added update required for OpenNMS 33.0.4

if [ $# = 1 ]
then
   if [ $1 = "rundis" ]
   then
      echo $(date +%Y%m%d%H%M%S) > /opt/opennms/.forcerundis
   fi   
fi

#extract version to link to configuration
rpm -q opennms > /tmp/opennms.version
ONS_VERS=$(cat /tmp/opennms.version)

CUSTOMIZED_FILES="
 /tmp/opennms.version
 /home/opennms/etc/credentials.txt
 /home/opennms/etc/log4perl.conf
 /home/opennms/.opennms/provision.plrc
 /root/.cpan/CPAN/MyConfig.pm
 /root/.opennms/provision.plrc
 /opt/opennms/.ABBCS_Config_defaults/default-opennms.conf
 /opt/opennms/.ABBCS_Config_defaults/.installcode
 /opt/opennms/.ABBCS_Config_defaults/.opennms.creds
 /opt/opennms/.ABBCS_Config_defaults/default-opennms-datasources.xml
 /opt/opennms/.ABBCS_Config_defaults/pg_hba.conf.install
 /opt/opennms/.forcerundis
 /opt/opennms/scripts/*
 /opt/opennms/bin/checkwmi
 /opt/opennms/etc/collectd-configuration.xml
 /opt/opennms/etc/config.properties
 /opt/opennms/etc/datacollection-config.xml
 /opt/opennms/etc/datacollection/ABBCS*.xml
 /opt/opennms/etc/datacollection/JVM-MANAGEMENT-MIB.xml
 /opt/opennms/etc/datacollection/microsoft.xml
 /opt/opennms/etc/datacollection/netsnmp.xml
 /opt/opennms/etc/default-foreign-source.xml
 /opt/opennms/etc/destinationPaths.xml
 /opt/opennms/etc/eventconf.xml
 /opt/opennms/etc/eventd-configuration.xml
 /opt/opennms/etc/events/ABBCS*.xml
 /opt/opennms/etc/events/JVM-MANAGEMENT-MIB.events.xml
 /opt/opennms/etc/events/LinuxKernel.syslog.events.xml
 /opt/opennms/etc/events/NetSNMP.events.xml
 /opt/opennms/etc/events/opennms.collectd.events.xml
 /opt/opennms/etc/events/opennms.internal.events.xml
 /opt/opennms/etc/events/opennms.pollerd.events.xml
 /opt/opennms/etc/events/opennms.snmp.trap.translator.events.xml
 /opt/opennms/etc/events/OpenSSH.syslog.events.xml
 /opt/opennms/etc/events/Oracle.events.xml
 /opt/opennms/etc/events/programmatic.events.xml
 /opt/opennms/etc/events/Rancid.events.xml
 /opt/opennms/etc/events/Sudo.syslog.events.xml
 /opt/opennms/etc/events/Syslogd.events.xml
 /opt/opennms/etc/events/Uptime.events.xml
 /opt/opennms/etc/foreign-sources/Appliance.xml
 /opt/opennms/etc/foreign-sources/Databases.xml
 /opt/opennms/etc/foreign-sources/OpenNMSServers.xml
 /opt/opennms/etc/foreign-sources/Servers.xml
 /opt/opennms/etc/foreign-sources/Windows_Servers.xml
 /opt/opennms/etc/foreign-sources/WebSite.xml
 /opt/opennms/etc/jdbc-datacollection-config.xml
 /opt/opennms/etc/jetty.xml
 /opt/opennms/etc/jmx-config.xml
 /opt/opennms/etc/jmx.acl.org.apache.karaf.bundle.cfg
 /opt/opennms/etc/jmx.acl.org.apache.karaf.config.cfg
 /opt/opennms/etc/jmx.acl.org.apache.karaf.security.jmx.cfg
 /opt/opennms/etc/log4j2.xml
 /opt/opennms/etc/notifd-configuration.xml
 /opt/opennms/etc/notificationCommands.xml
 /opt/opennms/etc/notifications.xml
 /opt/opennms/etc/opennms.keystore
 /opt/opennms/etc/opennms.properties
 /opt/opennms/etc/opennms.properties.d/ABBCS.properties
 /opt/opennms/etc/org.apache.karaf.command.acl.feature.cfg
 /opt/opennms/etc/org.apache.karaf.command.acl.jaas.cfg
 /opt/opennms/etc/org.apache.karaf.command.acl.kar.cfg
 /opt/opennms/etc/org.apache.karaf.command.acl.system.cfg
 /opt/opennms/etc/org.apache.karaf.features.repos.cfg
 /opt/opennms/etc/org.apache.karaf.features.cfg
 /opt/opennms/etc/org.apache.karaf.kar.cfg
 /opt/opennms/etc/org.apache.karaf.management.cfg
 /opt/opennms/etc/org.opennms.features.datachoices.cfg
 /opt/opennms/etc/org.opennms.features.topology.app.cfg
 /opt/opennms/etc/org.ops4j.pax.url.mvn.cfg
 /opt/opennms/etc/poller-configuration.xml
 /opt/opennms/etc/scv.jce
 /opt/opennms/etc/service-configuration.xml
 /opt/opennms/etc/surveillance-views.xml
 /opt/opennms/etc/syslog/ABBCS*
 /opt/opennms/etc/syslogd-configuration.xml
 /opt/opennms/etc/snmp-graph.properties.d/ABBCS*
 /opt/opennms/etc/snmp-graph.properties.d/JVM-MANAGEMENT-MIB-graph.properties
 /opt/opennms/etc/snmp-graph.properties.d/netsnmp-graph.properties
 /opt/opennms/etc/threshd-configuration.xml
 /opt/opennms/etc/thresholds.xml
 /opt/opennms/etc/users.xml
 /opt/opennms/etc/xml-datacollection-config.xml
 /opt/opennms/etc/xml-datacollection/ABBCS*
 /opt/opennms/etc/org.ops4j.pax.url.mvn.cfg
 /opt/opennms/etc/org.ops4j.pax.logging.cfg	
 /opt/opennms/jetty-webapps/opennms/WEB-INF/applicationContext-spring-security.xml
 /opt/opennms/jetty-webapps/opennms/WEB-INF/spring-security.d/GMS_activeDirectory.xml
 /opt/opennms/jetty-webapps/updates.xml
 /opt/opennms/lib/mssql-jdbc*
 /var/opennms/mibs/compiled/JVM-MANAGEMENT-MIB.mib
 /opt/rfinteg/etc/api-keys
 /opt/rfinteg/etc/category.map
 /opt/rfinteg/etc/logger.conf
 /etc/cron.daily/update_opennms
 /etc/init.d/opennms_customisations
 /etc/logrotate.d/rfinteg
 /etc/logrotate.d/opennms*
 /etc/rsyslog.conf
 /etc/rsyslog.d/00-custom.conf
 /etc/security/limits.conf
 /etc/sudoers.d/gms
 /etc/testsvr
 /etc/testsvr.d/.ssh/authorized_keys
 /etc/testsvr.d/.ssh/id_rsa
 /etc/testsvr.d/.ssh/id_rsa.pub 
 /etc/yum/pluginconf.d/versionlock.list
 /etc/yum.repos.d/opennms-repo-stable-rhel7*
 /etc/yum.repos.d/mssql-release.repo
 /etc/yum.repos.d/pgdg-redhat-all.repo
 /etc/pki/rpm-gpg/*
 /var/lib/pgsql/15/data/pg_hba.conf
 /var/lib/pgsql/15/data/postgresql.conf
 /var/spool/cron/opennms
 /var/spool/cron/rfinteg
 /var/spool/cron/rfoutages
"

### Files with local customisations (Cannot be copied across all servers)
#/opt/opennms/etc/discovery-configuration.xml
#/opt/opennms/etc/poll-outages.xml
#/opt/opennms/etc/snmp-config.xml

# List of files/directories that need to be saved for config transfer
CUSTOMIZED_FILES_LOCAL="
 /tmp/opennms.version
 /home/opennms
 /opt/opennms/.ABBCS_Config_defaults
 /opt/opennms/etc/collectd-configuration.xml
 /opt/opennms/etc/opennms.conf
 /opt/opennms/etc/discovery-configuration.xml
 /opt/opennms/etc/foreign-sources/Databases.xml
 /opt/opennms/etc/imports/[!Appliance]*.xml
 /opt/opennms/etc/ksc-performance-reports.xml
 /opt/opennms/etc/notifd-configuration.xml
 /opt/opennms/etc/opennms-datasources.xml
 /opt/opennms/etc/poll-outages.xml
 /opt/opennms/etc/poller-configuration.xml
 /opt/opennms/etc/snmp-config.xml
 /opt/opennms/etc/threshd-configuration.xml
 /opt/opennms/etc/wmi-config.xml
 /opt/rfinteg/etc/local_category.map
 /var/opennms/rrd/snmp/fs
 /etc/snmp/snmpd.conf
 /oracle/product/12.1.0.1_SE/network/admin/tnsnames.ora
" 


DEST=/opt/opennms_save_config
LOCAL_BACKUPS=$DEST/backups
HOST=$(hostname)
DATE=$(date "+%Y%m%d%H%M%S")
FILE_LIST_NAME=$DEST/OpenNMSConfigUpdates.txt
INSTALL_CODE=/opt/opennms/.ABBCS_Config_defaults/.installcode

TARBALL=$DEST/ABBCS_opennms_config_${HOST}_${DATE}_${ONS_VERS}.tgz
LOCAL_CONFIG_BACKUP="$LOCAL_BACKUPS/local_opennms_config_${HOST}_${ONS_VERS}_${DATE}.tgz"


# check if there has been an upgrade but rpmnew or rpmsave files have not been addressed.
RPMNEW=$(find /opt/opennms -name \*rpmnew -print | wc -l)
RPMSAVE=$(find /opt/opennms -name \*rpmsave -print | wc -l)

if [ $RPMNEW -gt 0 -o $RPMSAVE -gt 0 ]
then
  echo "ERROR: Found .rpmnew or .rpmsave files in /opt/opennms directory."
  echo "Opennms Upgrade has been performed but changes to config files have not been incorporated"
  echo "If this is being run on the Master Opennms server, please check/merge .rpmnew and .rpmsave"
  echo "changes before re-runing this script. "
  echo 
  echo "Creation of backup aborted"
  exit 1
fi

if [ ! -d $DEST ]
then
   mkdir -p $DEST
fi

if [ ! -d $LOCAL_BACKUPS ]
then
   mkdir -p $LOCAL_BACKUPS
fi

# set yum version lock
/opt/opennms/scripts/ons_version.sh -l

tar cvzpf $TARBALL $CUSTOMIZED_FILES
tar czf "${LOCAL_CONFIG_BACKUP}" --ignore-failed-read --exclude=/home/opennms/backups --exclude=/home/opennms/logs $CUSTOMIZED_FILES_LOCAL

openssl enc -aes-256-cbc -e -in $TARBALL -out ${TARBALL}.x -pass file:${INSTALL_CODE}

cd $DEST
ls -1r ABBCS*.x | openssl enc -aes-256-cbc -e -out $FILE_LIST_NAME -pass file:${INSTALL_CODE}

chown opennms $TARBALL $LOCAL_CONFIG_BACKUP ${TARBALL}.x $FILE_LIST_NAME
chmod 600 $TARBALL $LOCAL_CONFIG_BACKUP ${TARBALL}.x $FILE_LIST_NAME
chown opennms $TARBALL $LOCAL_CONFIG_BACKUP ${TARBALL} $FILE_LIST_NAME
chmod 600 $TARBALL $LOCAL_CONFIG_BACKUP ${TARBALL} $FILE_LIST_NAME


echo
echo Config saved to $TARBALL
echo Local Customnisations saved to ${LOCAL_CONFIG_BACKUP}



/opt/opennms/scripts/check_sendevent.sh


