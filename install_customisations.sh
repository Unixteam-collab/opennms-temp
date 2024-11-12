#!/bin/bash 

#
#  Program:   install_customisations.sh
#
#  Purpose:   To retrieve a saved configuration from another opennms server to install on this server.
#             Without the "-i" option, configuration will not be installed, instead, differences will
#             be displayed on screen.
#
#             After the 1st run, the source opennms server is stored in a defaults file and used for future
#             script executions.  Script will also generate an ssh key to be added to the source opennms 
#             user's authorized keys file
#
#             Script will upgrade OpenNMS if source configuration is for a later version.
#             (OpenNMS downgrade is not supported with this script)
#             
#             Check the differences before using -i option to ensure sanity of proposed configuration change.
#            
#               -q option provided to enable configuration automation
#
#             Setting "TICKET_NEEDED" in $CONFIG_DEFAULTS to true will cause script to exit if RF ticket parameter
#             is not specified
#
#  Side effects:
#           - running this script will create $CONFIG_DIR if it does not exist,
#             and populate it with the following files:
#               defaults
#               opennms_update-key
#           - Restarts opennms, cron, snmpd and rsyslog
#           - Configures opennms users home directory for Batch monitoring
#           - if "extract_customisations.sh" script has been executed with "rundis" parameter,
#             then this script will run "install -dis"
#               (if "install -dis" has never been run by this script, it will force run "install -dis")
#           - Upgrades Opennms if downloaded configuration is for a later version.
#           - Will delete any configuration file called OPENNMS_BASE/*/ABBCS* which is
#             not distributed in the updated configuration
#           - sets ownership of /opt/rfinteg/var to rfinteg user
#           - when -i option specified, a 15 minute outage will be put in place for the OpenNMS server notifications
#             starting from the current time.
#             Script will also attempt to create an outage on nodes listed in ONS_OUTAGE_HOSTS to suppress notifications
#             from remote ONS servers monitoring this server.
#             To cater for remote outages, script will create OpenNMSServers requisition on non localhost nodes in
#             ONS_OUTAGE_HOSTS if it doesn't already exist, and add this server to that requisition if not already there. 
#           - updates $CONFIG_DEFAULTS if there are defaults missing from the file.
#           - Uninstalls java8 and ensures java-11-openjdk is installed
#           - Installs postgresql-15
#           - Upgrades OpenNMS Postgresql database if it is less than V15
#
#  Assumptions:
#           - OpenNMS repository access pre-configured via spacewalk or manually enabled via /etc/yum.repos.d/opennms*
#           - Microsoft repository access pre-configured via spacewalk or manually enabled via /etc/yum.repos.d/mssql*
#
#  Author:   John Blackburn
#
#  Version:  2.68
#
#  History:  1.0  JDB 2017-05-10  Initial Revision
#            1.1  JDB 2017-05-12  Added code to store default opennms server to sync from
#            1.2  JDB 2017-05-16  Added restart of rsyslog due to deployment of rsyslog configuration
#            1.3  JDB 2017-05-23  Added -q option to assist configuration deployment automation
#            1.4  JDB 2017-06-02  Updated wording of progress output
#            1.5  JDB 2017-06-19  Added code to read defaults even if a source server is specified
#                                 Added code to fail if conection to specified source OpenNMS server doesn't work
#            1.6  JDB 2017-06-21  Added code to send SIGHUP to crontab due to opennms crontab being deployed
#                                 Added code to build batch monitoring directory structure in opennms users home
#            1.7  JDB 2017-07-07  Added code to run "install -dis" if requested
#            1.8  JDB 2017-07-13  Perform upgrade of opennms if source is higher version
#            1.9  JDB 2017-07-14  Moved script version check earlier to reduce instances
#                                 when script won't run due to checks exiting before the
#                                 re-run code is reached.
#            1.10 JDB 2017-07-14  Activated code to perform yum update
#            1.11 JDB 2017-07-17  Added more timestamps to logfile to assist determing timings of different parts of this script.
#            1.12 JDB 2017-07-21  moved check for CONFIG_DIR before it is accessed
#            1.13 JDB 2017-07-21  Removed line of code that was allowing "AUTOMATED_INSTALL" variable to be added twice
#                                 to configuration file
#            1.14 JDB 2017-07-26  Added code to remove ABBCS* files to cleanup configfiles that have been removed from master
#            1.15 JDB 2017-07-26  Variablised /opt/opennms and /home/opennms
#            1.16 JDB 2017-08-03  Added code to install package dependencies
#            1.17 JDB 2017-08-28  Modified downgrade detection so that configuration differences can still be displayed.
#            1.18 JDB 2017-08-29  Allow install to occur if the only difference is that new files are added.
#            1.19 JDB 2017-08-29  Added code to allow mandatory RF ticket number on select servers
#            1.20 JDB 2017-09-05  Added code to add defaults for web submission of RF tickets.
#            1.21 JDB 2017-09-06  Correct permissions on /opt/rfinteg/var
#            1.22 JDB 2017-09-12  Added code to add default for UpdateIP
#            1.24 JDB 2017-09-20  Added code to preserve locally defined outages.
#                                 Added code to create a 15 minute outage for OpenNMS server this script is running on
#            1.25 JDB 2017-09-28  Set default DOMAIN for UpdateIP
#            1.26 JDB 2017-09-29  Fixed ONS_NODE_ID query so it doesn't output an error on 1st execution
#            1.27 JDB 2017-10-03  Fixed defaults file generation code
#            1.28 JDB 2017-10-05  updated to cater for ONS server having FQDN node name in ONS
#            1.29 JDB 2017-10-10  Added restart of snmpd
#            1.30 JDB 2017-10-10  Added code to create ONS outage on a remote monitor
#            1.31 JDB 2017-10-11  OpenNMS servers live in the OpenNMSServers Requisition when being remotely monitored
#                                 to be able to restrict remote monitoring notifications.  Modifed to be able to find 
#                                 OpenNMS node on remote server.
#            1.32 JDB 2017-10-12  localhost outage needs to have common name
#            1.33 JDB 2017-10-12  Added OpenNMSMon snmp group to snmpd configuration that only returns time so script knows
#                                 what community string to query
#            1.34 JDB 2017-10-16  Added restart of postgresql due to postgresql config file changes being deployed
#            1.35 JDB 2017-10-18  Functionised setting of default environment variables
#                                 Added configurable delay for "-a" option
#            1.36 JDB 2017-10-18  Added code to add this opennms server to OpenNMSServers requisition on ONS_OUTAGE_HOSTS
#                                 if it doesn't already exist.
#            1.37 JDB 2017-10-20  Output current configuration details
#            2.00 JDB 2017-11-22  Added full ONS installation code
#            2.01 JDB 2017-12-05  Moved create opennms outage code to its own script so it can be used elsewhere
#                                 Swapped diff parameters so that output is more logical
#            2.02 JDB 2017-12-06  Added code to backup local customisations to source opennms server so that local customisations
#                                 can be transfered in the event a rebuild is required
#            2.03 JDB 2017-12-07  Added DeJavu font packages required for depencency (dependency failure was on non-azure opennms server)
#            2.04 JDB 2017-12-08  Install rsync for local config backup
#                                 Backup automatically transfered to source opennms server
#            2.05 JDB 2017-12-11  Updated comments added to defaults file (will only affect new installations)
#            2.06 JDB 2017-12-13  added hostname to remote backup destination directory
#            2.07 JDB 2018-01-03  Added code to specify different outage length for ONS upgrade
#            2.08 JDB 2018-01-05  Added call to fix_rrd.sh to move ForeignSource based RRD data from NodeID based location
#            2.09 JDB 2018-02-26  Install CIFS monitoring plugin
#            2.10 JDB 2018-03-01  Added -f optipon to force running of script when there are no changes.
#            2.11 JDB 2018-03-19  modified yum update to yum update-to to prevent yum from installing too high a version of opennms
#                                 Modified to correctly set CURRENT_VER variable during a configuration restoration.
#            2.12 JDB 2018-04-04  As installing customised configuration breaks the OpenNMSConfigUpdate outage, there was a small window during
#                                 execution of this script when OpenNMS was started without the OpenNMSConfigUpdate outage in place.  This 
#                                 left it possible for OpenNMS to raise a Remedy Force ticket about OpenNMS being down.  Added code to disable
#                                 notifd before stopping opennms, and then re-enabling it after the outage links have been restored.
#            2.13 JDB 2018-04-20  Added cronie to package dependencies as it is no longer installed by default in Azure deployed VM's
#            2.14 JDB 2018-05-04  Added jq to package dependencies for scripted JSON file processing
#            2.15 JDB 2018-05-24  Increased Upgrade outage time to 40 minutes
#            2.16 JDB 2018-05-30  Added install of perl ODBC SqlServer drivers and Oracle monitoring dependencies
#            2.17 JDB 2018-06-07  Moved installation of Oracle releated perl modules until after Oracle client is installed.
#            2.18 JDB 2018-06-07  Fix backup rsync command so that on 1st run, directory is created on backup destination
#                                 rather than a file containing the backup data.
#            2.19 JDB 2018-06-08  ensure OL7 Addons repository is enabled when installing jq
#            2.20 JDB 2018-06-25  Install Perl Config::IniFiles
#            2.21 JDB 2018-07-03  Cleanup old/failed requisition imports
#            2.22 JDB 2018-07-11  Install OpenJDK (and remove Oracle JDK if installed)
#            2.23 JDB 2018-07-12  Tweeked log output (less going to screen, more going to logfile...)
#            2.24 JDB 2018-07-16  Moved configuration backup to after outage link restoration
#            2.25 JDB 2018-08-08  Install vim
#            2.26 JDB 2018-08-08  Fix commandline parameter save to better handle when there are spaces in paramaters
#            2.27 JDB 2018-10-22  Use yum versionlock to lock opennms version.  Change to not force install from internet repo.
#                                 Assume Spacewalk channel is set to ol7_opennms
#            2.28 JDB 2018-10-24  Update output redirection
#            2.29 JDB 2018-11-02  Correct handling of outages for packages that contain spaces in the name
#            2.30 JDB 2018-11-08  Check if opennms repository is enabled through spacewalk or if the public repo should be enabled
#            2.31 JDB 2018-12-05  Add call to update opennms on boot (to cater for servers that aren't running by default at 3am.
#                                (auto schedule servers miss out on updates due to always being down at the standard update time)
#            2.32 JDB 2018-12-10  added code to allow opennms-helm to be conditionally updated
#            2.33 JDB 2019-02-25  removed direct install of msodbcsql17, and rely on that package being pulled in via dependencies
#                                 of mssql-tools, because as of 25th Feb 2019, the version of msodbcsql17 that direct install attempts
#                                 to install is incompatible with the latest available version of mssql-tools.
#                                 NOTE: mssql-tools and msodbcsql17 package versions locked in ons_version.sh to ensure that OS patching
#                                 does not fail due to attempt to upgrade mssqlodbcsql17 when compatible mssql-tools is not available.
#            2.34 JDB 2019-03-08  Fixed handling of yum repo source
#            2.35 JDB 2019-03-22  Added install of perl-Archive-Tar
#            2.36 JDB 2019-03-25  Added code to allow proxy config for CPAN access if required.  Added cpan to list of packages to install incase it is missing.
#            2.37 JDB 2019-05-02  Install OpenJDK-11 (and remove any version of java-1.8 that is installed)
#            2.38 JDB 2019-05-22  install List::Util
#            2.39 JDB 2019-05-22  changed Log4perl install from cpan to yum
#            2.40 JDB 2019-08-02  configure CPAN by deploying MyConfig.pm and updating proxy settings instead of deleting and re-genterating
#            2.41 JDB 2019-08-22  changed DBD::ODBC, Parse::CPAN::Meta, YAML installs from cpan to yum
#            2.42 JDB 2019-08-28  ensure perl-XML-DOM is installed
#            2.43 JDB 2019-09-04  deploy default opennms-datasources.xml if opennms server still has original
#            2.44 JDB 2019-09-12  fix "runjava" output redirection
#            2.45 JDB 2019-09-24  log "-t" parameter to $REASON_LOG for posterity
#            2.46 JDB 2019-10-02  Updated for openNMS 25 including installing PostgreSQL 11.5
#            2.47 JDB 2019-10-16  install wmic
#            2.48 JDB 2019-12-18  Updated to fetch updates via Web interface 
#            2.49 JDB 2020-01-15  Added code to allow customisation of JAVA_HEAP_SIZE
#            2.50 JDB 2020-01-15  Allow generation of ssh key even though we have added WEB access
#            2.51 JDB 2020-01-20  Install perl-DBD-Pg
#            2.52 JDB 2020-02-17  Install perl module DBIx::Log4perl from cpan
#            2.53 JDB 2020-02-21  Added code to prevent script failure when run following a previous run that failed due to network
#                                 disconnect prior to user interaction required for setup of ssh/ssl keys
#            2.54 JDB 2020-03-12  Change default value for "USE_OPSGENIE" flag to true
#            2.55 JDB 2020-03-16  Change all existing opennms servers to USE_OPSGENIE to true
#            2.56 JDB 2020-04-08  Added ksh package install
#            2.57 JDB 2020-04-29  Added code to allow for customer CA when accessing OpsGenie
#            2.58 JDB 2020-04-29  Delete the OpenNMS config update outage once opennms is back up as it sometimes doesn't stop automatically
#            2.59 JDB 2020-04-30  move cpan installs outside of opennms downtime to prevent cpan access failures from delaying opennms start
#            2.60 JDB 2020-05-07  Install perl module LWP::Protocol::connect from cpan
#            2.61 JDB 2020-05-20  fixed permissions on rfoutage user's home directory
#            2.62 JDB 2020-05-25  Change default value for "USE_RF" flag to false
#            2.63 JDB 2020-06-10  Added "-o StrictHostKeyChecking=no" parameter to ssh and scp (needed for Jenkins deploy)
#            2.64 JDB 2020-06-12  remove libjq before installing jq due to conflict between libjq 1.5 and jq 1.6.1
#            2.65 JDB 2020-06-22  Raise ticket if version upgrade fails.
#            2.66 JDB 2020-07-20  Try to better guess sandpit servers so Jenkins automation build does not start spamming support queues
#            2.67 JDB 2021-12-15  Updates required for OpenNMS 29.0.3 and Mitigation for CVE-2021-44228 and CVE-2021-45046
#            2.68 JDB 2024-06-21  Updates required for OpenNMS 33.0.4 including PG 15 upgrade
#                                  
# 
   
OBSOLETE_FILES="
 /opt/opennms/etc/events/AlarmChangeNotifierEvents.xml
 /opt/opennms/etc/scripts/EllipseBatch/check_ellipse_batch_longrun_new.pl
 "

OPENNMS_BASE=/opt/opennms
OPENNMS_HOMEDIR=/home/opennms
SOURCE_LOCATION=/opt/opennms_save_config
STAGING=/opt/opennms_config_stage
LOGDIR=$STAGING/logs
LOGFILE=$LOGDIR/config_update.log
REASON_LOG=$LOGDIR/install_reason.txt
BACKUP=$STAGING/backup
WORK=$STAGING/work
CONFIG_DIR=${OPENNMS_BASE}/.ABBCS_Config_defaults
CONFIG_DEFAULTS=${CONFIG_DIR}/defaults
OPENNMS_CONFIG_DEFAULT=${CONFIG_DIR}/default-opennms.conf
OPENNMS_CONFIG_FILE=$OPENNMS_BASE/etc/opennms.conf
SOURCE_USER=opennms
KEY=${CONFIG_DIR}/opennms_update-key
INSTALL_CODE=${CONFIG_DIR}/.installcode
CURRENT_VER=$(rpm -q opennms)

export WORK
if [ "$CURRENT_VER" = "package opennms is not installed" ]
then
  IS_ONS_INSTALLED=false
else
  IS_ONS_INSTALLED=true
fi

STANDARD_OUTAGE_LENGTH=30
UPGRADE_OUTAGE_LENGTH=60

# check repo config.
yum repolist | grep opennms > /dev/null 2>&1

if [ $? != 0 ]
then
   ENABLE_ONS_REPO='--enablerepo=opennms*'
   ENABLE_MSSQL_REPO='--enablerepo=mssql*'
else
   ENABLE_ONS_REPO=''
   ENABLE_MSSQL_REPO=''
fi



usage() {
   echo "Usage: $0 [-n X] [-l] [-i] [-q] [-a] [-f] [-t RFTicket] [-c filename] [<opennms source>] " >&2
   echo "    -l    - List available configs" >&2
   echo "    -n X  - specify a configuration to install" >&2
   echo "    -q    - query if local customisations vary from current lastest available on source ">&2
   echo "    -i    - interactive installation of configuration (Without this option, script will only display differences)" >&2
   echo "    -a    - automated installation option.  This can be overridden by updating $CONFIG_DEFAULTS ">&2
   echo "    -f    - force run of installation even if there are no changes to files" >&2
   echo "    -t X  - Remedy Force ticket number.  Mandatory if TICKET_NEEDED=true is specified in $CONFIG_DEFAULTS" >&2
   echo "    -c Filename  - Restore configuration from file (used for opennms rebuild)" >&2
   echo "" >&2
   echo "  The query option is designed for monitoring, so most output is suppressed." >&2
   echo "    NOTE: -q and -l options should not be used together from an automated process" >&2
   echo "          due to -l option requiring user input" >&2
   echo "" >&2
   echo "  example:" >&2
   echo "    $0 acm_opennms01" >&2
   echo "    $0 -l acm_opennms01" >&2
   echo "    $0 -in 1 acm_opennms01" >&2
   echo "    $0 -i -t 00654213" >&2
   exit 1
}



# SET_ENV function sets an environment variable if it is not already defined in $CONFIG_DEFAULTS
# If it is not set, then add it to $CONFIG_DEFAULTS
SET_ENV()
{
   # parameters:
   #   1 - Variable to set
   #   2 - Value to assign to variable if not set
   #   3 - comment to add to CONFIG_DEFAULTS to assist future manual editing of configuration
   if [ -v $1 ]
   then 
      echo $1 = \"$(eval "echo \$$(eval echo $1)")\" | tee -a $LOGFILE
   else
      echo Setting $1.  Update $CONFIG_DEFAULTS to override. | tee -a $LOGFILE
      echo "$3" >> $CONFIG_DEFAULTS
      echo "$1=\"$2\"" >> $CONFIG_DEFAULTS
      eval "$1=\"$2\""
      echo $1 = \"$2\" | tee -a $LOGFILE
   fi
}


#### Code to raise RF ticket
RFINTEG_INCOMING_DIR=/opt/rfinteg/var/incoming
HOSTNAME=$(hostname)
NODE=$HOSTNAME
EVENTID=commandline
NOTICEID=$(basename $0)
SEVERITY=warning
RESOURCEID=OpenNMSInstallCustomisations
CATEGORY="Operating System"


notify() {
  #### Code to raise RF ticket
  EVENT="${HOSTNAME}:${NODE}:${EVENTID}:${NOTICEID}"
  MESSAGEKEY="${HOSTNAME}:${NODE}:${SEVERITY}:${RESOURCEID}"
   
  EVENT_FILE="${RFINTEG_INCOMING_DIR}/${EVENT}"
  
  echo $NODE > $EVENT_FILE
  echo ${SEVERITY,,} >> $EVENT_FILE
  echo $EVENT >> $EVENT_FILE
  echo $1 >> $EVENT_FILE
  echo $CATEGORY >> $EVENT_FILE
  echo $MESSAGEKEY >> $EVENT_FILE
  echo $MESSAGEKEY >> $EVENT_FILE
  echo >> $EVENT_FILE
  echo >> $EVENT_FILE
  echo $ENV_TYPE >> $EVENT_FILE
  

  #echo RF Ticket Raising disabled...
  echo $1 | tee -a $LOGFILE

}

# Code for saving outage configurations
NOTIFICATIONS=$OPENNMS_BASE/etc/notifd-configuration.xml
POLLERD=$OPENNMS_BASE/etc/poller-configuration.xml
COLLECTD=$OPENNMS_BASE/etc/collectd-configuration.xml
THRESHD=$OPENNMS_BASE/etc/threshd-configuration.xml

#TRANSFER_FILE="$HOSTNAME_$CURRENT_VER.tgz"


NOTIF_OUT=""
POLLERD_OUT=""
COLLECTD_OUT=""
THRESHD_OUT=""

get_outages ()
{
  FILE=$1
  while read a b
  do
     if [ "$a" = '<package' ]
     then
        PKG=$(echo "$b" | cut -d\" -f2 | sed 's/ /%20/g')
     fi

     c=$(echo $a| awk ' BEGIN { FS = "[<>]" } {  print $2 } ')
     if [ "$c" = 'outage-calendar' ]
     then
        OUTAGE=$(echo $a $b| awk ' BEGIN { FS = "[<>]" } {  print $3 } ')
        echo "$PKG $OUTAGE"
     fi
  done < $FILE
}

delete_outages ()
{  
   TYPE=$1
   OUTAGES="$2"

   if [ "X$OUTAGES" != "X" ]
   then
     if [ $TYPE = 'notifd' ]
     then
        echo Notifd outages:
        echo "$OUTAGES"
        echo "$OUTAGES" | while read OUT
        do
          curl -X DELETE "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')/$TYPE"
        done
     else
        echo Other outages:
        echo "$OUTAGES"
        echo "$OUTAGES" | while read PKG OUT
        do
          curl -X DELETE "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')/$TYPE/$PKG"
        done
     fi
   fi
}

restore_outages ()
{  
   TYPE=$1
   OUTAGES="$2"

   if [ "X$OUTAGES" != "X" ]
   then
     echo restoring outages:
     echo   $TYPE
     echo "$OUTAGES"
     if [ $TYPE = 'notifd' ]
     then
        echo "$OUTAGES" | while read OUT
        do
          if [ "$(curl "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')" 2>/dev/null)" = "Scheduled outage $OUT was not found." ]
          then
            echo Outage \"$OUT\" not found.  Not restoring link to $TYPE
            curl -X DELETE "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')/$TYPE"
          else
            echo Outage \"$OUT\" found.  Restoring link to $TYPE
            curl -X DELETE "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')/$TYPE"
            curl -X PUT "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')/$TYPE"
          fi
        done
     else
        echo "$OUTAGES" | while read PKG OUT
        do
          if [ "$(curl "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')"2>/dev/null)" = "Scheduled outage $OUT was not found." ]
          then
            echo Outage \"$OUT\" not found.  Not restoring link to $TYPE/$PKG
            curl -X DELETE "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')/$TYPE/$PKG"
          else
            echo Outage \"$OUT\" found.  Restoring link to $TYPE/$PKG
            curl -X DELETE "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')/$TYPE/$PKG"
            curl -X PUT "http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/sched-outages/$(echo $OUT|sed 's/ /%20/g')/$TYPE/$PKG"
          fi
        done
     fi
   else
     echo no outages to restore for $TYPE
   fi
}

update_opennms_conf ()
{
  VARIABLE=$1
  VALUE="$2"

  sed -i "s/^\($VARIABLE\s*=\s*\).*\$/\1$VALUE/" $OPENNMS_CONFIG_FILE
   
}

if [ $# -lt 1 ]
then
   usage
fi

DO_INSTALL=false
LIST_CONFIG=false
QUERY=false
AUTO_INSTALL=false
RF_TICKET=undefined
DO_ONS_INSTALL=false
RESTORE_CONFIG=false

# default to latest configuration
SELECT_CONFIG=1

if [ ! -d $STAGING ]
then
   mkdir -p $STAGING
fi

if [ ! -d $LOGDIR ]
then
   mkdir -p $LOGDIR
fi

date >> $LOGFILE

# Preserve command line for re-processing if script has a newer version
SAVE_OPTS=()
for i in "$@"; do
    SAVE_OPTS+=("'$i'")
done


MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized

echo commandline = "$MY_PATH ${SAVE_OPTS[@]}" >> $LOGFILE

GOT_CHANGES=false

while getopts "ln:iqaft:c:" opt; do
    case "${opt}" in
        l)
            LIST_CONFIG=true
            ;;
        n)
            SELECT_CONFIG=${OPTARG}
            if ! [[ $SELECT_CONFIG =~ ^[0-9]+$ ]]
            then
               echo "Missing Configuration number" >&2
               usage
            fi
            ;;
        i)
            if $QUERY 
            then
               echo "ERROR -i and -q options are mutually exclusive" >&2
               usage
            fi
            DO_INSTALL=true
            ;;
        q)
            if $DO_INSTALL
            then
               echo "ERROR -i and -q options are mutually exclusive" >&2
               usage
            fi
            QUERY=true
            ;;
        a)
            if $QUERY
            then
               echo "ERROR -a and -q options are mutually exclusive" >&2
               usage
            fi
            AUTO_INSTALL=true
            DO_INSTALL=true
            ;;
        f)
            GOT_CHANGES=true
            ;;
        t)
            RF_TICKET="${OPTARG}"
            ;;
        c)
            RESTORE_CONFIG=true
            TRANSFER_FILE=${OPTARG}
            if [ ! -f $TRANSFER_FILE ]
            then
               echo "ERROR: $TRANSFER_FILE does not exist" >&2
               exit 1
            fi
            ;;
        :)
            echo "Option: -$OPTARG requires an argument." >&2
            usage
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -v TRANSFER_FILE ]
then
   TF_PATH=$(dirname $TRANSFER_FILE) # relative
   TF_PATH="`( cd \"$TF_PATH\" && pwd )`"  # absolutized and normalized
   TRANSFER_FILE="${TF_PATH}/$(basename $TRANSFER_FILE)"  # absolutized and normalized
fi

case  "$#" in
    0)
       if [ -f $CONFIG_DEFAULTS ]
       then
          if ! $QUERY
          then
            echo OpenNMS source server not specified, loading defaults from $CONFIG_DEFAULTS
          fi
          . $CONFIG_DEFAULTS
       else
          echo "ERROR: Unable to determine source Opennms Server.  Please specify on commandline" >&2 
          usage
       fi
       ;;
    1)
       echo Source Opennms server specified $1
       if [ -f $CONFIG_DEFAULTS ]
       then
          . $CONFIG_DEFAULTS
       fi
       SOURCE_SERVER=$1
       ;;
    *)
       echo "Too many parameters" >&2
       usage
       ;;
esac

# Determine Install source Type: either WEB or SSH
#    install installation dependencies
yum -y install nmap-ncat curl openssl >> $LOGFILE 2>&1

nc -w 5 $SOURCE_SERVER 443 < /dev/null > /dev/null 2>&1
if [ $? == 0 ]
then
   INSTALL_TYPE=WEB
   INSTALL_URL="https://$SOURCE_SERVER/updates"
else
   echo nc -w 5 $SOURCE_SERVER 8980
   nc -w 5 $SOURCE_SERVER 8980 < /dev/null > /dev/null 2>&1
   if [ $? == 0 ]
   then
      INSTALL_TYPE=WEB
      INSTALL_URL="http://$SOURCE_SERVER:8980/updates"
   else
      INSTALL_TYPE=SSH
   fi
fi

export INSTALL_TYPE INSTALL_URL

if [ ! -d $CONFIG_DIR ]
then
   if $QUERY
   then
      # exit script in query mode if not configured to ensure that if monitoring triggers this script
      # without it being configured, it does not sit around for ever waiting for user input
      echo "ERROR: Query mode is designed for monitoring, and requires script to be pre-configured." >&2
      echo "  Please re-run without -q option to allow script to initialise." >&2
      usage
   fi
   echo
   echo NOTICE: Not configured. Configuring...
   echo 
   if [ $RESTORE_CONFIG = true ]
   then
      echo Restoring config from $TRANSFER_FILE
      cd /
      tar xvpf $TRANSFER_FILE | tee -a $LOGFILE
   else
      mkdir -p $CONFIG_DIR
   fi
fi

### set up both WEB and SSH codes - replacement for scp backup of configuration not yet implemented
if [ ! -f $INSTALL_CODE ]
then
   if $QUERY
   then
      # exit script in query mode if not configured to ensure that if monitoring triggers this script
      # without it being configured, it does not sit around for ever waiting for user input
      echo "ERROR: Query mode is designed for monitoring, and requires script to be pre-configured." >&2
      echo "  Please re-run without -q option to allow script to initialise." >&2
      usage
   fi
   
   # The following test has been added to protect automated execution of script on existing openNMS servers from hanging if they
   # are not currently configured to use the encrypted version, as this code change moves the code requiring user input outside
   # of the protection of the the "unconfigured" detection code
   if $AUTO_INSTALL
   then
       echo WARNING: Auto install option selected but installcode not found. | tee -a $LOGFILE
   else
      echo Please enter OpenNMS Install code from Azure Teampass
      read CODE
      if [ $CODE = "" ]
      then
         echo  ERROR: OpenNMS Install code can\'t be empty
         exit
      fi
      echo $CODE > $INSTALL_CODE
      chmod 600 $INSTALL_CODE
   fi
fi
if [ ! -f $CONFIG_DIR/opennms_update-key.pub ]
then
   if $QUERY
   then
      # exit script in query mode if not configured to ensure that if monitoring triggers this script
      # without it being configured, it does not sit around for ever waiting for user input
      echo "ERROR: Query mode is designed for monitoring, and requires script to be pre-configured." >&2
      echo "  Please re-run without -q option to allow script to initialise." >&2
      usage
   fi
   # The following test has been added to protect automated execution of script on existing openNMS servers from hanging if they
   # are not currently configured to use the encrypted version, as this code change moves the code requiring user input outside
   # of the protection of the the "unconfigured" detection code
   if $AUTO_INSTALL
   then
       echo WARNING: Auto install option selected but ssh key not found | tee -a $LOGFILE
   else
      echo  Setting up ssh-keys
      ssh-keygen -b 2048 -f $CONFIG_DIR/opennms_update-key -N ""

      echo
      echo 
      echo Please add the following line to opennms user\'s authorized_keys file on $SOURCE_SERVER  
      echo
      cat $CONFIG_DIR/opennms_update-key.pub
      echo
      echo Press enter to continue once the above authorised_keys file has been configured
      read a
   fi
fi

# force permission to 701 so that submit_ticket.pl script can read defaults
chmod 701 $CONFIG_DIR


if ! $QUERY 
then
   echo
   echo SOURCE_SERVER = $SOURCE_SERVER 
   echo
fi

# Save defaults if not set
if [ ! -f $CONFIG_DEFAULTS ]
then
  date >> $LOGFILE
  echo No defaults found.  Saving defaults to $CONFIG_DEFAULTS | tee -a $LOGFILE
  echo Seting ALLOW_AUTOMATED_INSTALL to true.  Update $CONFIG_DEFAULTS to override. | tee -a $LOGFILE
  echo SOURCE_SERVER=$SOURCE_SERVER > $CONFIG_DEFAULTS
fi

# if the monitoring ONS server is in the same time zone as this one, then the automated updates run
# concurrently on both servers, and the creation of ONS Update Outage may fail.
# AUTO_UPDATE_DELAY can be manually modified on an OpenNMS server to delay the automated update.
# Auto Update delay will only take effect if -a option specified

SET_ENV "AUTO_UPDATE_DELAY" "0" "# change AUTO_UPDATE_DELAY if automated update clashes with ONS_OUTAGE_HOST
# (value is in seconds)"
SET_ENV "ALLOW_AUTOMATED_INSTALL" "true" "# Set to false if server should only receive updates by manually running install_customisations scripts
# (only useful for the non-prod Management opennms servers where configuration updates are tested prior to pushing changes to general production)"

if $AUTO_INSTALL
then
   if ! $ALLOW_AUTOMATED_INSTALL
   then
     AUTO_INSTALL=false
     echo "ERROR: -a option specified but ALLOW_AUTOMATED_INSTALL = false" | tee -a $LOGFILE
     echo "    Aborting installation" | tee -a $LOGFILE
     date >> $LOGFILE
     exit 1
   fi
   UPDATE_DELAY=$AUTO_UPDATE_DELAY
else
   UPDATE_DELAY=0
fi

SET_ENV "TICKET_NEEDED" "false" "# Set to true if Remedy force ticket is required to push changes to this server"
SET_ENV "URI" "/cgi-bin/logcall_fqdn.pl" "# URI for Remedy Force ticket submission.
#   FQDN URI's require TOKEN ID field in Remedy Force to match capitoliszed node name from OpenNMS
#   non FQDN URI's require TOKEN ID field in Remedy Force to be truncated to 30 characters
#   PRIMARY is tried first, and if that fails, SECONDARY is tried.
#URI=/cgi-bin/logcall_prelim.pl
#URI=/cgi-bin/logcall.pl
#URI=/cgi-bin/logcall_fqdn_prelim.pl"
SET_ENV "PRIMARY" "aue-s-rfinteg01" "# Primary Remedy Force Integration server"
SET_ENV "SECONDARY" "usw-s-rfinteg01" "# secondary Remedy Force Integration server"
SET_ENV "UPDATE_IP" "AUTO" "# UPDATE_IP - valid values: AUTO, MANUAL"
SET_ENV "DNS_AUTHORITY" "10.2.0.6" "# DNS_AUTHORITY=10.1.0.7
# DNS_AUTHORITY=192.55.198.156"
SET_ENV "DOMAIN" "gms.mincom.com" "# DOMAIN used to lookup IP addresses by update_ip.sh
# can contain multiple space separated values if required"

SET_ENV "ONS_OUTAGE_HOSTS" "localhost" "#OPENNMS servers that monitor this server and require an outage to prevent false alerts during scheduled restart
# localhost entry must always be in variable"

SET_ENV "USE_PROXY" "false" "# Set this to true when OpenNMS server has no direct access to internet and configure proxy definition below
# use 'connect' when going through a proxy requiring authentication
# proxy=http://74.112.221.249:3128
# proxy=connect://user:password@proxy.customer.com:5200"

# defaults for USE_RF and USE_OPSGENIE should be set for current ticketing system
SET_ENV "USE_RF" "false" "# Set to true to cause tickets to be raised with Remedy Force"
SET_ENV "USE_OPSGENIE" "true" "# Set to true to cause tickets to be raised with OpsGenie"
SET_ENV "USE_CUSTOMER_CA" "false" "# Set to true when Opsgenie access passes though customer firewall where certificate gets replaced"
SET_ENV "CUSTOMER_CA_PATH" "/home/opennms/etc/CustCAFile.pem" "# Set to location of customer Certificate authority cert"
SET_ENV "ONS_JAVA_HEAP" 8192 "# OpenNMS Java heap Size"

#set default alerting priority basis
# This is a crude initial guess based on the 8th character of the opennms hostname
# which will be mostly correct for azure hosts
ENV_GUESS=$(hostname | cut -c8)
case "$ENV_GUESS" in
   n|d)
     ENV_GUESS=non-prod
     ;;
   s)
     ENV_GUESS=sandpit
     ;;
   *)
     ENV_GUESS=prod
     ;;
esac

if [ $(hostname | cut -c-3) = 'acm' ]
then
   ENV_GUESS=sandpit
fi

#if [ "$ENV_GUESS" = 'n' ] || [ "$ENV_GUESS" = 'd' ]
#then
#   ENV_GUESS=non-prod
#else
#   ENV_GUESS=prod
#fi
SET_ENV "ENV_TYPE" "$ENV_GUESS" "# set to prod for prod environments and non-prod for others; sandpit for test opennms environment"


echo | tee -a $LOGFILE

if [ "$INSTALL_TYPE" = "WEB" ]
then
    echo Fetching update list via Web from $INSTALL_URL | tee -a $LOGFILE
    AVAILABLE=$(curl -q -k $INSTALL_URL/OpenNMSConfigUpdates.txt 2>/dev/null| openssl enc -aes-256-cbc -d -pass file:$INSTALL_CODE)
else 
    echo Fetching update list via ssh from $SOURCE_SERVER | tee -a $LOGFILE
    AVAILABLE=$(ssh -i $KEY opennms@$SOURCE_SERVER "cd $SOURCE_LOCATION; ls -1t ABBCS*")
    RESULT=$?
    if [ "$RESULT" != "0" ]
    then
       echo "ERROR: ssh connection to $SOURCE_SERVER failed" | tee -a $LOGFILE
       echo "    Aborting installation" | tee -a $LOGFILE
       exit 1
    fi
fi
date >> $LOGFILE



TOTAL=$(echo "$AVAILABLE"| wc -l)

if $RESTORE_CONFIG
then
   echo Please select a configuration that matches the version being restored
fi

if $LIST_CONFIG
then
   echo Available Configurations:
   COUNT=1
   for x in $AVAILABLE
   do
      echo $COUNT $x
      COUNT=$(( $COUNT + 1 ))
   done
   echo
   if $DO_INSTALL
   then
     echo -n "Please specify a configuration to install: "
   else
     echo -n "Please specify a configuration to compare: "
   fi
   read SELECT_CONFIG
   if ! [[ $SELECT_CONFIG =~ ^[0-9]+$ ]]
      then
         echo "Invalid response" >&2
         exit 1
   fi
fi

if [ $SELECT_CONFIG -lt 1 -o  $SELECT_CONFIG -gt $TOTAL ]
then
   echo "Selected configuration does not exist" | tee -a $LOGFILE 2>&1
   exit 1
else
   SELECTED_CONFIG=$(echo "$AVAILABLE"| head -$SELECT_CONFIG | tail -1)
fi

if ! $QUERY
then
  echo Configuration selected: $SELECTED_CONFIG | tee -a $LOGFILE
fi


date >> $LOGFILE
echo Copy selected configuration from source >> $LOGFILE

if [ $INSTALL_TYPE = 'SSH' ]
then
   echo Retriving selected config via SSH from $SOURCE_SERVER | tee -a $LOGFILE
   scp -o StrictHostKeyChecking=no -i $KEY $SOURCE_USER@$SOURCE_SERVER:${SOURCE_LOCATION}/$SELECTED_CONFIG $STAGING >> $LOGFILE 2>&1
else
   echo Retriving selected config via web from $INSTALL_URL | tee -a $LOGFILE
   curl -k $INSTALL_URL/$SELECTED_CONFIG > $STAGING/$SELECTED_CONFIG 2>> $LOGFILE
fi

# if selecteted config ends with ".x" then pass through openssl 
if [ "${SELECTED_CONFIG:$((${#SELECTED_CONFIG}-1)):1}" = "x" ]
then
   echo Decoding config file | tee -a $LOGFILE
   X_SELECTED_CONFIG=$SELECTED_CONFIG
   SELECTED_CONFIG=${X_SELECTED_CONFIG%.*}

   cat $STAGING/$X_SELECTED_CONFIG | openssl enc -aes-256-cbc -d  -pass file:/opt/opennms/.ABBCS_Config_defaults/.installcode > $STAGING/$SELECTED_CONFIG
fi


date >> $LOGFILE
if [ ! -d $BACKUP ]
then 
   mkdir -p $BACKUP
fi

if [ -d $WORK ]
then 
   rm -rf $WORK
fi

mkdir $WORK

cd $WORK

# grab "extract_customisations.sh" script from incoming script

date >> $LOGFILE
echo Extracting configuration to staging directory >> $LOGFILE
tar xvpf "${STAGING}/${SELECTED_CONFIG}" >> $LOGFILE 2>&1

# due to notifications usually being disabled when config distribution tarball is created
# we force the status back to on so the comparison doesn't see this as a difference that it cares about
# otherwise, automated config update would always run even if there was no changes to install.
sed -i 's/status="off"/status="on"/' $WORK/$NOTIFICATIONS >> $LOGFILE 2>&1

# Check for updated install_customistaions scipt.

CUR_SUM=$(cksum $MY_PATH/$(basename $0) | awk '{print $1}')
NEW_SUM=$(cksum $WORK/opt/opennms/scripts/$(basename $0) | awk '{print $1}')


if [ "$CUR_SUM" != "$NEW_SUM" ]
then

   if $QUERY
   then
     notify "Version Mismatch: $(basename $0)"
     date >> $LOGFILE
     exit 3
   else
     echo | tee -a $LOGFILE
     echo | tee -a $LOGFILE
     echo "WARNING: $(basename $0) has been updated." | tee -a $LOGFILE
     echo | tee -a $LOGFILE
     if $AUTO_INSTALL
     then
        echo "Automated installation requested, restarting script automatically" | tee -a $LOGFILE
     else
        echo "Press enter to restart with new script or Ctrl-C to abort"
        read
     fi
     date >> $LOGFILE
     eval $WORK/opt/opennms/scripts/$(basename $0) ${SAVE_OPTS[@]}
     exit 0
   fi
fi

# Version Check

CONFIG_VER=$(cat $WORK/tmp/opennms.version)
VER_NUM=$(echo $CONFIG_VER | cut -c9-)
ONS_EXTRA_PACKAGES="opennms-plugin-protocol-cifs-$VER_NUM"

if rpm -q opennms-helm > /dev/null
then
  ONS_EXTRA_PACKAGES="${ONS_EXTRA_PACKAGES} opennms-helm"
fi 

FORCERUNDIS=false
DOUPGRADE=false
DOWNGRADE_DETECTED=false

if $IS_ONS_INSTALLED
then
   if [ "$CURRENT_VER" != "$CONFIG_VER" ]
   then
     FORCERUNDIS=true
     if [ "$CURRENT_VER" \< "$CONFIG_VER" ]
     then
        echo | tee -a $LOGFILE
        echo "Opennms Version Upgrade.  $CURRENT_VER to $CONFIG_VER" | tee -a $LOGFILE
        DOUPGRADE=true
     else
        if $QUERY
        then
           notify "Version Mismatch: OpenNMS downgrade attempt detected. $CURRENT_VERSION to $CONFIG_VER"
        else
           echo | tee -a $LOGFILE
           echo "####### VERSION DOWNGRADE ########" | tee -a $LOGFILE
           echo "  attempt to install configuration from $CONFIG_VER" | tee -a $LOGFILE
           echo "  however $CURRENT_VER is currently installed" | tee -a $LOGFILE
           echo "  Version downgrade is not possible with this script" | tee -a $LOGFILE
           echo  | tee -a $LOGFILE
        fi
        date >> $LOGFILE
        # Set flag here instead of exiting so that configuration differences can still be displayed
        DOWNGRADE_DETECTED=true
        #exit 2
     fi
   fi

   # Check if "install -dis" needs to be run
   if [ -f $WORK/opt/opennms/.forcerundis ]
   then
      RUNDIS=$(cat $WORK/opt/opennms/.forcerundis)
      if [ -f ${OPENNMS_BASE}/.lastrundis ]
      then
         LASTRUN=$(cat ${OPENNMS_BASE}/.lastrundis)
      else
         LASTRUN=NEVER
      fi
      if [ $RUNDIS != $LASTRUN ]
      then
         FORCERUNDIS=true
      fi
   fi

   if ! $DO_INSTALL
   then 
     if ! $QUERY
     then 
        echo This update contains the following changes: | tee -a $LOGFILE
     fi
   else
     echo This update will apply the following changes: | tee -a $LOGFILE
   fi

   for file in $(find . -type f -print)
   do
      DIFF_OUT="$(diff /$file $file)"
      DIFF_RES=$?
      if (( $DIFF_RES >= 1 ))
      then
        GOT_CHANGES=true
        if ! $QUERY
        then
           # suppress output for -q option 
           # Limit output to only those files that have differences
           echo | tee -a $LOGFILE
           echo diff /$file $file | tee -a $LOGFILE
           echo "$DIFF_OUT" | tee -a $LOGFILE
        fi
      fi
   done
else
   echo OpenNMS not currently installed. | tee -a $LOGFILE
   GOT_CHANGES=true
   FORCERUNDIS=true
   DO_ONS_INSTALL=true
fi

date >> $LOGFILE

if ! $GOT_CHANGES
then
   if $QUERY
   then
      echo "Ok" | tee -a $LOGFILE
   else 
      echo | tee -a $LOGFILE
      echo There are no changes to apply.  Exiting script. | tee -a $LOGFILE
   fi
   exit 0
fi

if $QUERY
then
  # if we got this far in query mode then the current config differs from the source so raise a ticket
  notify 'Configuration differences'
  exit 1
fi

if $DO_INSTALL
then

  if [ $TICKET_NEEDED = 'true' ]
  then
     echo -n "$(date) " >> $REASON_LOG
     echo -n "$(who am i) " >> $REASON_LOG
     if [ "$RF_TICKET" = "undefined" ]
     then
       echo "ERROR: This server ($HOSTNAME) reqires a Remedy Force ticket to install changes" | tee -a $LOGFILE
       echo "    Aborting installation" | tee -a $LOGFILE
       date >> $LOGFILE
       echo "Reason required but not supplied.  Updates not applied" >> $REASON_LOG
       exit 1
     fi
     echo $RF_TICKET >> $REASON_LOG
     echo "Remedy Force ticket: $RF_TICKET" | tee -a $LOGFILE
  fi

  if [ $DOWNGRADE_DETECTED = 'true' ]
  then
     # prevent install if configuration being installed is for an earlier version.
     # this code has been put in so that the configuration diff output can still be
     # viewed when OpenNMS upgrade is being tested.
     echo Downgrade detected.  Aborting installing | tee -a $LOGFILE
     date >> $LOGFILE
     exit 2
  fi

  # if monitoring ONS server is in the same time zone as this one, then the automated updates run
  # concurrently on both servers, and the creation of ONS Update Outage may fail.
  date | tee -a $LOGFILE
  echo Update Delay has been set to $UPDATE_DELAY Seconds.  Please wait | tee -a $LOGFILE
  sleep $UPDATE_DELAY
  echo Update Delay complete | tee -a $LOGFILE
  date | tee -a $LOGFILE

  # ensure GPG keys imported
  rpm --import /etc/pki/rpm-gpg/*  >> $LOGFILE 2>&1


  # check user accounts
  if [ $(grep -c ^rfinteg /etc/group) = 0 ]
  then
     groupadd -g 1001 rfinteg
  fi

  if [ $(grep -c ^rfinteg /etc/passwd) = 0 ]
  then
     useradd -u 1001 -g 1001 -c "Remedy Force Integration - `hostname`" -d /opt/rfinteg -m rfinteg
  fi

  if [ $(grep -c ^opennms /etc/passwd) = 0 ]
  then
     useradd -c "opennms user - `hostname`" -d $OPENNMS_HOMEDIR -m opennms 2>&1 >>$LOGFILE
  fi

  if [ $(grep -c ^rfoutages /etc/passwd) = 0 ]
  then
     useradd -u 1003 -g 1001 -c "RFoutages upload user - `hostname`" -d /etc/testsvr.d -m rfoutages 2>&1 >>$LOGFILE
  fi

  #fix permissions on rfoutage users directory so that rfinteg user can view
  chmod g+rx /etc/testsvr.d

  echo Checking package dependencies | tee -a $LOGFILE
  # OpenNMS dependencies
  # Note: as of 14/May/2018, it appears that cronie is back in the Azure Market place build, but no harm trying to install it.
  yum -y install bind-utils sysstat net-snmp net-snmp-utils cronie vim yum-versionlock ksh firewalld >> $LOGFILE 2>&1
  yum -y install rrdtool jrrd2>> $LOGFILE 2>&1
  #yum -y --enablerepo=ol7\*addons install jq>> $LOGFILE 2>&1
  # conflict with libjq 1.5 and jq 1.6.1, so uninstall libjq before attempting to install jq
  yum -y remove libjq >> $LOGFILE 2>&1
  yum -y install jq>> $LOGFILE 2>&1
  yum -y localinstall ${WORK}/opt/opennms/scripts/Utilities/wmi-1.3.14-4.el7.art.x86_64.rpm >> $LOGFILE 2>&1

  echo Installing dependencies for SQL Server monitoring | tee -a $LOGFILE
  # install dependencies for SQL Server monitoring
  ACCEPT_EULA=Y
  export ACCEPT_EULA
  #yum -y --enablerepo=mssql\* install perl-DBI msodbcsql17 mssql-tools unixODBC-devel perl-CPAN >> $LOGFILE 2>&1
  #yum -y $ENABLE_MSSQL_REPO install perl-DBI msodbcsql17 mssql-tools unixODBC-devel perl-CPAN >> $LOGFILE 2>&1
  # removed msodbcsql17 as installing mssql-tools by itself ensures that compatible msodbcsql17 version is installed
  # issue is that as of 25-2-2019, mssql-tools available to install is currently incompatible with latest version of msodbcsql17
  #

  echo Installing required perl modules | tee -a $LOGFILE
  yum -y $ENABLE_MSSQL_REPO install cpan gcc perl-DBI perl-Archive-Tar mssql-tools unixODBC-devel perl-CPAN perl-JSON perl-String-Escape perl-Switch bzip2 wget curl patch perl-XML-DOM perl-CPAN-DistnameInfo bc>> $LOGFILE 2>&1

  date | tee -a $LOGFILE

  if $IS_ONS_INSTALLED
  then
     . $CONFIG_DIR/.opennms.creds
     # Save existing outage links
     NOTIF_OUT=$(awk ' { FS = "[<>]" } $2 == "outage-calendar" { print $3 }' $NOTIFICATIONS)
     POLLERD_OUT="$(get_outages $POLLERD)"
     COLLECTD_OUT="$(get_outages $COLLECTD)"
     THRESHD_OUT="$(get_outages $THRESHD)"

     echo "Current outage links" | tee -a $LOGFILE
     echo "Notification outages" = "$NOTIF_OUT" | tee -a $LOGFILE
     echo "Pollerd      outages" = "$POLLERD_OUT" | tee -a $LOGFILE
     echo "Collectd     outages" = "$COLLECTD_OUT" | tee -a $LOGFILE
     echo "Threshd      outages" = "$THRESHD_OUT" | tee -a $LOGFILE


     # backup existing config
     echo | tee -a $LOGFILE
     echo Backing up existing configuration | tee -a $LOGFILE
     echo | tee -a $LOGFILE
     $WORK/opt/opennms/scripts/extract_customisations.sh >> $LOGFILE 2>&1


     # Disable notification Daemon
     sed -i 's/status="on"/status="off"/' $NOTIFICATIONS >> $LOGFILE 2>&1


     # Delete existing outage links. 
     # This is to ensure that outage links defined on a "source" OpenNMS server are
     # not transfered to other OpenNMS servers
     delete_outages notifd "$NOTIF_OUT" >> $LOGFILE 2>&1
     delete_outages pollerd "$POLLERD_OUT" >> $LOGFILE 2>&1
     delete_outages collectd "$COLLECTD_OUT" >> $LOGFILE 2>&1
     delete_outages threshd "$THRESHD_OUT" >> $LOGFILE 2>&1

     date | tee -a $LOGFILE

     echo Creating outage to suppress events from OpenNMS server during update | tee -a $LOGFILE
     if [ $DOUPGRADE = 'true' ]
     then
        ONS_OUTAGE_LENGTH=$UPGRADE_OUTAGE_LENGTH
     else
        ONS_OUTAGE_LENGTH=$STANDARD_OUTAGE_LENGTH
     fi
     $WORK/opt/opennms/scripts/ons_outage.sh $ONS_OUTAGE_LENGTH | tee -a $LOGFILE 2>&1

     echo "Migrate NodeID based rrd data to Foreign Source Based if required" | tee -a $LOGFILE
     ${WORK}/opt/opennms/scripts/fix_rrd.sh >> $LOGFILE 2>&1

     echo Stopping Opennms | tee -a $LOGFILE
     date >> $LOGFILE
     systemctl stop opennms >> $LOGFILE 2>&1

     if [ $USE_PROXY = 'true' ]
     then
        http_proxy=$proxy
        https_proxy=$proxy
        ftp_proxy=$proxy
        export http_proxy https_proxy ftp_proxy
     fi

     echo Checking PostgresSQL version | tee -a $LOGFILE
     cp $WORK/etc/yum.repos.d/pgdg-redhat-all.repo /etc/yum.repos.d

     ${WORK}/opt/opennms/scripts/check_postgresql.sh 2>&1 | tee -a $LOGFILE

     if [ $? != 0 ]
     then
        date >> $LOGFILE
        echo failed to upgrade/install postgresql | tee -a $LOGFILE
        exit 1
     fi
     if [ $DOUPGRADE = 'true' ]
     then
        date >> $LOGFILE
        echo Check java version | tee -a $LOGFILE
        yum -q list installed jdk1.8\* &>/dev/null && (yum -y swap -- remove jdk1.8\* -- install java-1.8.0-openjdk-devel) 2>&1 >>$LOGFILE
        yum install -y java-11-openjdk-devel 2>&1 >>$LOGFILE
        /opt/opennms/bin/runjava -s 2>&1 >>$LOGFILE
        echo Upgrading Opennms | tee -a $LOGFILE
        yum versionlock clear 2>&1 >>$LOGFILE
        #yum update -y postgresql postgresql-libs postgresql-server 2>&1 >> $LOGFILE
        #yum update-to -y --enablerepo=opennms\* $CONFIG_VER $ONS_EXTRA_PACKAGES  2>&1 >> $LOGFILE
        yum update-to -y $ENABLE_ONS_REPO $CONFIG_VER $ONS_EXTRA_PACKAGES  2>&1 >> $LOGFILE
        #/opt/opennms/bin/fix-permissions 2>&1 >> $LOGFILE
        chown -R opennms /home/opennms
        # new version of opennms runs as opennms user. leftover /tmp/opennms* directories owned by root can break opennms restart
        rm -rf /tmp/opennms* >> $LOGFILE

        if [ $? != 0 ]
        then
           notify "ERROR: failed to update Opennms to $CONFIG_VER. See $(hostname):$LOGFILE"
           echo ERROR: failed to upgrade to $CONFIG_VER.  Unable to proceed.  | tee -a $LOGFILE
           echo     See $LOGFILE for more details
           exit 1
        fi
     fi
  fi
  date >> $LOGFILE

  if $DO_ONS_INSTALL
  then
     if [ ! -v SNMP_COMMUNITY ]
     then
        echo -n "Please enter SNMP COMMUNITY string (for azure servers, use resource group name) :"
        read SNMP
        SET_ENV SNMP_COMMUNITY "$SNMP" "# SNMP Community"
     fi
        
     if [ $(grep -c 'includeDir /etc/snmp/config.d' /etc/snmp/snmpd.conf) == 0 ]
     then

        # Set up SNMP
        MYNETWORK=$(ifconfig | grep inet\  | head -1 | awk '{ print $2}' | awk -F. '{ print $1 "." $2 "." $3 }')
        cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.preons
        cat >> /etc/snmp/snmpd.conf <<!EOF
   com2sec mynetwork 127.0.0.1 $SNMP_COMMUNITY
   com2sec mynetwork $MYNETWORK.0/24 $SNMP_COMMUNITY
   group MyROGroup v1 mynetwork
   group MyROGroup v2c mynetwork
   view all included .1
   access MyROGroup "" any noauth exact all none none
   syslocation Unknown (edit /etc/snmp/snmpd.conf)
   syscontact Root  (configure /etc/snmp/snmp.local.conf)

   ignoreDisk /dev/shm
   ignoreDisk /run
   ignoreDisk /sys/fs/cgroup
   includeAllDisks 10%

   skipNFSInHostResources 1

   # include all *.conf files in a directory
   includeDir /etc/snmp/config.d
!EOF
     fi
     mkdir /etc/snmp/config.d
     chmod go-rw /etc/snmp/config.d
     systemctl enable snmpd
     systemctl start snmpd

     echo "Please ensure the file $HOSTNAME:/opt/opennms/etc/snmp-config.xml contains the following entry:
   <definition read-community=\"$SNMP_COMMUNITY\">
      <range begin=\"$MYNETWORK.1\" end=\"$MYNETWORK.254\"/>
   </definition>" 



     cp $WORK/etc/yum.repos.d/opennms* /etc/yum.repos.d
     cp $WORK/etc/yum.repos.d/pgdg-redhat-all.repo /etc/yum.repos.d

     #yum -y install postgresql postgresql-libs postgresql-server java-11-openjdk java-11-openjdk-devel 2>&1 >>$LOGFILE
     yum -y install postgresql15-server java-11-openjdk java-11-openjdk-devel 2>&1 >>$LOGFILE

     if [ $? != 0 ]
     then
        echo ERROR: failed to install postgres15 and/or java11.  Unable to proceed.  | tee -a $LOGFILE
        echo     See $LOGFILE for more details
        exit 1
     fi
     #$WORK/opt/opennms/scripts/check_postgresql.sh 2>&1 | tee -a $LOGFILE
     
     #MIRROR="yum.opennms.org"

     #rpm --import http://${MIRROR}/OPENNMS-GPG-KEY 2>&1 >>$LOGFILE
     #yum install -y --enablerepo=opennms\* $CONFIG_VER 2>&1 >>$LOGFILE
     yum versionlock clear 2>&1 >>$LOGFILE
     yum install -y $ENABLE_ONS_REPO $CONFIG_VER 2>&1 >>$LOGFILE
     if [ $? != 0 ]
     then
        echo ERROR: failed to install $CONFIG_VER.  Unable to proceed.  | tee -a $LOGFILE
        echo     See $LOGFILE for more details
        exit 1
     fi

     CURRENT_VER=$(rpm -q opennms)
     ${OPENNMS_BASE}/bin/runjava -s 2>&1 >> $LOGFILE
     
     echo Executing OpenNMS Bootstrap installer | tee -a $LOGFILE
     bash ${WORK}/opt/opennms/scripts/bootstrap-yum.sh >>${LOGFILE} 2>&1
  fi


  echo Stopping OpenNMS Postgresql database | tee -a $LOGFILE
  systemctl stop postgresql-15 >> $LOGFILE 2>&1
  echo Installing configuration. | tee -a $LOGFILE
  cd /
  rm ${OPENNMS_BASE}/etc/datacollection/ABBCS*
  rm ${OPENNMS_BASE}/etc/events/ABBCS*
  rm ${OPENNMS_BASE}/etc/snmp-graph.properties.d/ABBCS*
  rm ${OPENNMS_BASE}/etc/syslog/ABBCS*
  rm ${OPENNMS_BASE}/etc/xml-datacollection/ABBCS*
  rm -f ${OBSOLETE_FILES}

  if [ -f {$OPENNMS_BASE}/etc/pluginManifestData.xml ]
  then  
     mv ${OPENNMS_BASE}/etc/pluginManifestData.xml ${OPENNMS_BASE}/etc/pluginManifestData.xml.$(date  +%C%y%m%d%H%M)
  fi


  # Cleanup failed Requisition imports
  rm -f ${OPENNMS_BASE}/etc/imports/pending/*.xml.*
  # rm -f ${OPENNMS_BASE}/etc/foreign-sources/pending/*
  tar xvpf "${STAGING}/${SELECTED_CONFIG}" >> $LOGFILE 2>&1
  # Ensure installed configuration does not re-enable notifications as this should not be done until Outage configurations are restored
  sed -i 's/status="on"/status="off"/' $NOTIFICATIONS >> $LOGFILE 2>&1
  find ${OPENNMS_BASE} -name \*rpmnew -type f -exec /bin/rm {} \; | tee -a $LOGFILE
  find ${OPENNMS_BASE} -name \*rpmsave -type f -exec /bin/rm {} \; | tee -a $LOGFILE

  chgrp opennms ${OPENNMS_BASE}/etc/snmp-config.xml
  chmod g+rw ${OPENNMS_BASE}/etc/snmp-config.xml

  chown postgres:postgres /var/lib/pgsql/15/data

  # ensure boot time check for configuration updates is configured to run.
  chkconfig opennms_customisations resetpriorities


  echo Config install complete, restarting  | tee -a $LOGFILE
  date >> $LOGFILE

  echo Starting OpenNMS postgresql database | tee -a $LOGFILE
  systemctl start postgresql-15 >> $LOGFILE 2>&1

  echo Update OpenNMS DB password in datasources file | tee -a $LOGFILE
  xmllint --shell ${OPENNMS_BASE}/etc/opennms-datasources.xml <<EOF
cd //jdbc-data-source[@name='opennms']/@password
set \${scv:postgres:password|opennms}
cd //jdbc-data-source[@name='opennms-admin']/@password
set \${scv:postgres-admin:password|opennms}
save
EOF

  if $DO_ONS_INSTALL
  then
#     mv /var/lib/pgsql/15/data/pg_hba.conf /var/lib/pgsql/15/data/pg_hba.conf.orig
#     cp $CONFIG_DIR/pg_hba.conf.install /var/lib/pgsql/15/data/pg_hba.conf
#     chown postgres:postgres /var/lib/pgsql/15/data/pg_hba.conf
      echo Configring OpenNMS postgresql database | tee -a $LOGFILE
#
#     systemctl restart postgresql-15
#     DB_USER="opennms"
#     DB_PASS="opennms"
#
#     sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" >>${LOGFILE} 2>&1
#     sudo -u postgres psql -c "CREATE DATABASE opennms;" >>${LOGFILE} 2>&1
#     sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE opennms to ${DB_USER};" >>${LOGFILE} 2>&1
#
#     systemctl restart postgresql-15
#     ${OPENNMS_BASE}/scripts/check_datasource.sh >> $LOGFILE 2>&1
#     echo Running "${OPENNMS_BASE}/bin/install -dis" | tee -a $LOGFILE
#     ${OPENNMS_BASE}/bin/install -dis 2>&1 | tee -a $LOGFILE 
#
#     mv /var/lib/pgsql/15/data/pg_hba.conf /var/lib/pgsql/15/data/pg_hba.conf.inst
#     cp /var/lib/pgsql/15/data/pg_hba.conf.orig /var/lib/pgsql/15/data/pg_hba.conf
  fi 
 
  # fix /etc/snmp/config.d/OpenNMSMon.conf
  # Grab current community string
  SNMP_COMMUNITY=$(grep 127.0.0.1 /etc/snmp/snmpd.conf | grep com2sec | awk '{ print $4}')


  cat > /etc/snmp/config.d/OpenNMSMon.conf <<EOF
com2sec mynetwork 10.2.0.0/24 $SNMP_COMMUNITY
com2sec mynetwork 10.1.0.0/24 $SNMP_COMMUNITY
com2sec mynetwork 10.165.5.0/24 $SNMP_COMMUNITY
com2sec mynetwork 192.55.198.0/24 $SNMP_COMMUNITY

com2sec OpenNMSMon 127.0.0.1 OpenNMSMon
com2sec OpenNMSMon 10.0.0.0/8 OpenNMSMon

group OpenNMSMonGroup v2c OpenNMSMon
view Datetime included .1.3.6.1.2.1.25.1.2.0
access OpenNMSMonGroup "" any noauth exact Datetime none none

EOF

  
  # install Additional OpenNMS packages
  #yum -y --enablerepo=opennms\* install $ONS_EXTRA_PACKAGES >> $LOGFILE 2>&1
  yum -y install $ONS_EXTRA_PACKAGES >> $LOGFILE 2>&1

  # Check if Oracle JDK is installed and replace with openjdk
  echo Checking Java version | tee -a $LOGFILE
  yum -q list installed jdk1.8\* &>/dev/null && (yum -y swap -- remove jdk1.8\* -- install java-1.8.0-openjdk-devel) 2>&1 >>$LOGFILE
  yum -y install java-11-openjdk-devel 2>&1 >>$LOGFILE
  /opt/opennms/bin/runjava -s 2>&1 >>$LOGFILE


  systemctl daemon-reload >> $LOGFILE 2>&1
  systemctl restart rsyslog >> $LOGFILE 2>&1
  systemctl restart snmpd >> $LOGFILE 2>&1

  if [ $FORCERUNDIS = 'true' ]
  then
      date >> $LOGFILE

      #mv /var/lib/pgsql/15/data/pg_hba.conf /var/lib/pgsql/15/data/pg_hba.conf.orig
      #cp $CONFIG_DIR/pg_hba.conf.install /var/lib/pgsql/15/data/pg_hba.conf
      #chown postgres:postgres /var/lib/pgsql/15/data/pg_hba.conf
      #systemctl restart postgresql-15 >> $LOGFILE 2>&1
      /opt/opennms/bin/fix-permissions 2>&1 >> $LOGFILE
      echo Running "${OPENNMS_BASE}/bin/install -dis" | tee -a $LOGFILE
      cp $WORK/opt/opennms/etc/scv.jce $OPENNMS_BASE}/etc/scv.jce
      ${OPENNMS_BASE}/bin/install -dis 2>&1 | tee -a $LOGFILE 
      cp ${OPENNMS_BASE}/.forcerundis ${OPENNMS_BASE}/.lastrundis
      #mv /var/lib/pgsql/15/data/pg_hba.conf /var/lib/pgsql/15/data/pg_hba.conf.install
      #cp /var/lib/pgsql/15/data/pg_hba.conf.orig /var/lib/pgsql/15/data/pg_hba.conf
      #chown postgres:postgres /var/lib/pgsql/15/data/pg_hba.conf
      #systemctl restart postgresql-15
  fi

  if [ $RESTORE_CONFIG = true ]
  then
     echo Restoring config from $TRANSFER_FILE
     cd /
     tar xvpf $TRANSFER_FILE tmp/opennms.version | tee -a $LOGFILE
     if [ "$( cat /tmp/opennms.version)" != "$CURRENT_VER" ]
     then
        echo WARNING: Restore version mismatch.  not restoring configuration | tee -a $LOGFILE
     else
        tar xvpf $TRANSFER_FILE | tee -a $LOGFILE
     fi
  fi

  # install default custom opennms-datasources.xml if not already installed
  $OPENNMS_BASE/scripts/check_datasource.sh >> $LOGFILE 2>&1
  
  echo Ensure OpenNMS JAVA_HEAP_SIZE is set to $ONS_JAVA_HEAP | tee -a $LOGFILE
  cp $OPENNMS_CONFIG_DEFAULT $OPENNMS_CONFIG_FILE
  update_opennms_conf JAVA_HEAP_SIZE $ONS_JAVA_HEAP >> $LOGFILE 2>&1
  if [ $ONS_JAVA_HEAP -ge "4096" ]
  then 
     echo "Java heap > 4g, setting G1GC" | tee -a $LOGFILE
     update_opennms_conf GC '\"-XX:+UseG1GC -XX:+UseStringDeduplication -XX:MaxGCPauseMillis=200 -XX:InitiatingHeapOccupancyPercent=45 -XX:+UseCompressedOops -Xlog:gc*:\/var\/log\/opennms\/gc.log\"'
  else
     echo "Java heap < 4g, setting ParallelGC" | tee -a $LOGFILE
     update_opennms_conf GC '\"-XX:+UseParallelGC -Xlog:gc*:\/var\/log\/opennms\/gc.log\"'
  fi
  date | tee -a $LOGFILE

  echo Firewall update | tee -a $LOGFILE
  systemctl enable firewalld | tee -a $LOGFILE
  systemctl start firewalld | tee -a $LOGFILE
  firewall-cmd --add-service https --permanent >> $LOGFILE 2>&1
  firewall-cmd --add-port 5817/tcp --add-port 8980/tcp --add-port 8443/tcp --add-port 3128/tcp --permanent >> $LOGFILE 2>&1
  firewall-cmd --add-port 161/tcp --add-port 161/udp --permanent >> $LOGFILE 2>&1
  firewall-cmd --add-port 162/tcp --add-port 162/udp --permanent >> $LOGFILE 2>&1
  firewall-cmd --add-port 514/tcp --add-port 514/udp --permanent >> $LOGFILE 2>&1
  # enable masquerade to allow port-forwards
  firewall-cmd --add-masquerade --permanent >> $LOGFILE 2>&1
  # forward port 162 TCP and UDP to port 1162 on localhost
  firewall-cmd --add-forward-port=port=162:proto=udp:toport=1162 --add-forward-port=port=162:proto=tcp:toport=1162 --permanent >> $LOGFILE 2>&1
  # forward port 514 TCP and UDP to port 1514 on localhost
  firewall-cmd --add-forward-port=port=514:proto=udp:toport=1514 --add-forward-port=port=514:proto=tcp:toport=1514 --permanent >> $LOGFILE 2>&1
  # forward port 443 TCP to port 8443 on localhost
  firewall-cmd --add-forward-port=port=443:proto=tcp:toport=8443 --permanent >> $LOGFILE 2>&1
  # Rules for the above with a source address of localhost:
  firewall-cmd --permanent --direct --add-rule ipv4 nat OUTPUT 0 -p tcp -o lo --dport 443 -j REDIRECT --to-ports 8443 >> $LOGFILE 2>&1
  firewall-cmd --permanent --direct --add-rule ipv4 nat OUTPUT 0 -p tcp -o lo --dport 162 -j REDIRECT --to-ports 1162 >> $LOGFILE 2>&1
  firewall-cmd --permanent --direct --add-rule ipv4 nat OUTPUT 0 -p udp -o lo --dport 162 -j REDIRECT --to-ports 1162 >> $LOGFILE 2>&1
  firewall-cmd --permanent --direct --add-rule ipv4 nat OUTPUT 0 -p tcp -o lo --dport 514 -j REDIRECT --to-ports 1514 >> $LOGFILE 2>&1
  firewall-cmd --permanent --direct --add-rule ipv4 nat OUTPUT 0 -p udp -o lo --dport 514 -j REDIRECT --to-ports 1514 >> $LOGFILE 2>&1
  
  firewall-cmd --reload >> $LOGFILE 2>&1

  /opt/opennms/bin/fix-permissions 2>&1 >> $LOGFILE
  echo Starting opennms | tee -a $LOGFILE
  systemctl enable opennms >> $LOGFILE 2>&1
  systemctl start opennms >> $LOGFILE 2>&1

  echo "Backgrounding Restoration of Outage Links" | tee -a $LOGFILE
  # this is enclosed in a for loop to ensure the loop does not run indefinitely,
  # and backgrounded so the script isn't delayed
  (for i in {1..360}
  do
    nc -w 5 localhost 8980 < /dev/null 2> /dev/null
    if [ $? -eq 0 ]
    then
       echo Finished waiting after $i waits
       break
    fi
    sleep 5
  done
  # code could be added here to handle loop hitting end (indicating opennms restart failed)

  if [ $USE_PROXY = 'true' ]
  then
     # we need to unset any proxy config as the outage config fails with it set.
     # NOTE: This is inside the restore outage subshell as there are CPAN commands
     # that are run after this subshell that still require the proxy settings
     unset http_proxy
     unset https_proxy
     unset ftp_proxy
  fi

  . $CONFIG_DIR/.opennms.creds

  restore_outages notifd "$NOTIF_OUT"
  restore_outages pollerd "$POLLERD_OUT"
  restore_outages collectd "$COLLECTD_OUT"
  restore_outages threshd "$THRESHD_OUT"

  sleep 5

  # Now that outages have been restored, it is safe to turn notifications back on
  sed -i 's/status="off"/status="on"/' $NOTIFICATIONS

  sleep 600
  # OpenNMS config update outage can be removed now that opennms is back up.
  delete_outages notifd OpenNMSConfigUpdate

  ) >> $LOGFILE 2>&1 &

  echo Installing cpan perl modules | tee -a $LOGFILE
  LANG=en_US
  PERL_MM_USE_DEFAULT=1
  export LANG PERL_MM_USE_DEFAULT

  PERL_MM_OPT=
  export PERL_MM_OPT

  unset PERL_MB_OPT PERL_LOCAL_LIB_ROOT PERL5LIB

  if [ $USE_PROXY = 'true' ]
  then
     CPPROX=$proxy
  else
     CPPROX=""
  fi
  # rm -rf /root/.cpan
  cpan >> $LOGFILE 2>&1 <<EOF
o conf http_proxy "$CPPROX"
o conf ftp_proxy "$CPPROX"
o conf commit
EOF

  cpan List::Util >> $LOGFILE 2>&1
  cpan Term::ReadKey >> $LOGFILE 2>&1
  cpan LWP::Protocol::connect >> $LOGFILE 2>&1
  #  cpan DBD::ODBC >> $LOGFILE 2>&1
  yum -y install perl-DBD-ODBC perl-DBD-Pg >> $LOGFILE 2>&1
 

  # install dependencies for Oracle monitoring
  #  -- moved to after oracle client is installed

  # install dependencies for OpsGenie Ticketing
  yum -y install perl-JSON-XS perl-LWP-Protocol-https perl-DateTime  >> $LOGFILE 2>&1

  # install dependencies for provision.pl
  yum -y install 'perl(LWP)' 'perl(XML::Twig)' >> $LOGFILE 2>&1

  # install dependencies for WMI monitoring
  yum -y install log4j slf4j perl-Log-Log4perl >> $LOGFILE 2>&1

  # install DBIx::Log4perl
  cpan DBIx::Log4perl >> $LOGFILE 2>&1

  # install dependencies for check_vpn.sh
  yum -y install nmap-ncat >> $LOGFILE 2>&1

  # rsync required for local config backup
  yum -y install rsync >> $LOGFILE 2>&1

  # install font dependencies
  yum -y install dejavu-fonts-common dejavu-sans-fonts dejavu-sans-mono-fonts >> $LOGFILE 2>&1

  # install additional dependencies
  ### Yum module for perl-Config-IniFiles not accessible on all opennms servers, so use CPAN
  #yum -y install perl-Config-IniFiles >> $LOGFILE 2>&1
  cpan Config::IniFiles >> $LOGFILE 2>&1
  echo Completed Checking package dependencies | tee -a $LOGFILE


  echo "Checking opennms user's home directory structure" | tee -a $LOGFILE
  mkdir -p ${OPENNMS_HOMEDIR}/etc ${OPENNMS_HOMEDIR}/logs ${OPENNMS_HOMEDIR}/.opennms
  chown opennms:opennms ${OPENNMS_HOMEDIR}/logs ${OPENNMS_HOMEDIR}/.opennms
  chown opennms:ssh-login@gms.mincom.com  ${OPENNMS_HOMEDIR}/etc
  chgrp ssh-login@gms.mincom.com ${OPENNMS_HOMEDIR}
  chmod 2770 ${OPENNMS_HOMEDIR}/etc
  chmod 750 ${OPENNMS_HOMEDIR}


  echo "Checking rfinteg user's directory structure" | tee -a $LOGFILE
  DIRLIST="/opt/rfinteg/var /opt/rfinteg/var/incoming /opt/rfinteg/etc /opt/rfinteg/var/current /opt/rfinteg/var/error /opt/rfinteg/var/locks"
  for DIR in $DIRLIST
  do
     if [ ! -d $DIR ]
     then
        echo "Making directory $DIR" >> $LOGFILE
        mkdir -p $DIR
     fi
  done
  chmod 755 /opt/rfinteg
  chown -R opennms:opennms /opt/rfinteg
  chmod 750 /opt/rfinteg/var
  chmod 2775 /opt/rfinteg/var/incoming


  pkill -HUP crond

# Set ticketing 
  ${OPENNMS_BASE}/scripts/set_ticketing.sh | tee -a $LOGFILE
  /opt/opennms/scripts/check_sendevent.sh

  echo "Backup updated config" | tee -a $LOGFILE
 

  ${OPENNMS_BASE}/scripts/extract_customisations.sh >> $LOGFILE 2>&1
  echo "Backup complete." | tee -a $LOGFILE

  if [ -x "${OPENNMS_BASE}/scripts/check_oracle.sh" ]
  then
     echo Installing Oracle Client | tee -a $LOGFILE
     ${OPENNMS_BASE}/scripts/check_oracle.sh 2>&1 >>  $LOGFILE 
  fi

  echo "Finalising Oracle Perl dependancies" | tee -a $LOGFILE
  yum -y  install perl-Parse-CPAN-Meta perl-YAML >> $LOGFILE 2>&1
  # for Oracle monitoring
  LD_LIBRARY_PATH=$(dirname $(find /oracle -name libclntsh.so 2> /dev/null))
  export LD_LIBRARY_PATH
  ORACLE_HOME=/oracle/product/12.1.0.1_SE
  export ORACLE_HOME
  # cpan YAML >> $LOGFILE 2>&1
  # cpan Parse::CPAN::Meta >> $LOGFILE 2>&1
  cpan install CPAN >> $LOGFILE 2>&1
  cpan DBD::Oracle >> $LOGFILE 2>&1


  date | tee -a $LOGFILE
  echo "Please wait 5 minutes for OpenNMS complete start up."
else

  if [ $DOUPGRADE = 'true' ]
  then
    echo
    echo "NOTE: This configuration is for a later version of Opennms.  Opennms will be upgraded when applying this update"
    echo "      $CURRENT_VER to $CONFIG_VER"
  fi
  if [ $FORCERUNDIS = 'true' ]
  then
    echo
    echo "NOTE: Force run of 'install -dis' has been triggered and would be run when applying this update"
  fi

  echo
  echo Please review the changes and if ok, rerun script with -i option.
  echo
  echo "Any files listed below will be removed with \"-i\" option:"
  find ${OPENNMS_BASE} -name \*rpmnew -print
  find ${OPENNMS_BASE} -name \*rpmsave -print
fi


if [ ! -d ${OPENNMS_HOMEDIR}/backups ]
then
   mkdir ${OPENNMS_HOMEDIR}/backups
   chown $SOURCE_USER ${OPENNMS_HOMEDIR}/backups
fi

date | tee -a $LOGFILE
echo Copy Local configuration backup to source opennms server | tee -a $LOGFILE
echo rsync -Pav -e "ssh -o StrictHostKeyChecking=no -i $KEY"  $SOURCE_LOCATION/backups/*${HOSTNAME}* $SOURCE_USER@$SOURCE_SERVER:/${OPENNMS_HOMEDIR}/backups/${HOSTNAME}/ >> $LOGFILE 2>&1
rsync -Pav -e "ssh -o StrictHostKeyChecking=no -i $KEY"  $SOURCE_LOCATION/backups/*${HOSTNAME}* $SOURCE_USER@$SOURCE_SERVER:/${OPENNMS_HOMEDIR}/backups/${HOSTNAME}/ >> $LOGFILE 2>&1

date | tee -a $LOGFILE
exit 0
