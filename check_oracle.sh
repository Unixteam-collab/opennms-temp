#!/bin/bash

# Program:  check_oracle.sh
#
# Purpose:  Check if oracle client is installed and if not, download and extract Oracle Client Install Pack
#
# Version:  1.2

# History:
#    1.0  27-11-2017 JDB   Initial Revision
#    1.1  18-04-2018 JDB   Added visual queue to indicate this script is running /home/oracle/oraInventory/orainstRoot.sh
#    1.2  26-10-2018 JDB   Modified to reset symlink for ojdbc.jar if needed

ORACLE_VERSION=12.1.0.1_SE
ORACLE_HOME_NAME=Oracle12101SE_client
ORACLE_BASE=/oracle
ORACLE_HOME=${ORACLE_BASE}/product/${ORACLE_VERSION}
OJDBC=${ORACLE_HOME}/jdbc/lib/ojdbc7.jar


OPENNMS_BASE=/opt/opennms
SOURCE_LOCATION=/opt/opennms_save_config
CONFIG_DIR=${OPENNMS_BASE}/.ABBCS_Config_defaults
CONFIG_DEFAULTS=${CONFIG_DIR}/defaults
SOURCE_USER=opennms
KEY=${CONFIG_DIR}/opennms_update-key
OJDBCLIB=${OPENNMS_BASE}/lib/ojdbc7.jar



. $CONFIG_DEFAULTS

TARBALL=Oracle_${ORACLE_VERSION}.tgz

usage() {
   echo "Usage: $0 [-x] " >&2
   echo "    -x - Extract Oracle Client for cloning to other OpenNMS servers" >&2
   exit 1
}


EXTRACT_ORA=false

while getopts "x" opt; do
    case "${opt}" in
        x)
            EXTRACT_ORA=true
            ;;
       *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if $EXTRACT_ORA
then
   if [ -f $SOURCE_LOCATION/$TARBALL ]
   then
      echo $SOURCE_LOCATION/$TARBALL already exists.
      echo To recreate, please delete first.
      exit 1
   fi
   echo Building Oracle Client pack
   tar czf $SOURCE_LOCATION/$TARBALL $ORACLE_HOME
   exit 0
fi

echo Checking Oracle Client install


date 
if [ ! -f $SOURCE_LOCATION/$TARBALL ]
then
   echo Copy selected configuration from source

   if [ $INSTALL_TYPE = 'SSH' ]
   then
      scp -i $KEY $SOURCE_USER@$SOURCE_SERVER:${SOURCE_LOCATION}/$TARBALL $SOURCE_LOCATION
   else
      curl -k $INSTALL_URL/$TARBALL > $SOURCE_LOCATION/$TARBALL
   fi

fi



if [ ! -d ${ORACLE_HOME}/jdbc/lib ]
then
   if [ ! -f $SOURCE_LOCATION/$TARBALL ]
   then
      echo Unable to locate Oracle Client installation bundle
      exit 1
   else
      echo Installing Oracle client prerequisists
      yum -y install oracle-rdbms-server-12cR1-preinstall xauth xclock
      echo Installing Oracle client
      groupadd -g 54321 oinstall
      groupadd -g 54322 dba
      useradd -u 54321 -g 54321 -m -d /home/oracle oracle
      mkdir -p /oracle
      chown oracle:oinstall /oracle
      tar xf $SOURCE_LOCATION/$TARBALL
      su oracle -c "$ORACLE_HOME/oui/bin/runInstaller -silent -clone ORACLE_BASE=$ORACLE_BASE ORACLE_HOME=$ORACLE_HOME ORACLE_HOME_NAME=$ORACLE_HOME_NAME -invPtrLoc=/etc"
      echo Running /home/oracle/oraInventory/orainstRoot.sh
      ( sleep 300; /home/oracle/oraInventory/orainstRoot.sh ) &
   fi
else
   echo Found Oracle Client.
fi

if [ ! -L $OJDBCLIB ]
then
   echo $OJDBCLIB not a symlink.  Fixing
   rm -f $OJDBCLIB
   ln -s $OJDBC $OJDBCLIB
else
   if [ $(readlink $OJDBCLIB) -ef $OJDBC ]
   then
      echo $OJDBCLIB link good
   else
      echo $OJDBCLIB link pointing to $(readlink $OJDBCLIB).  Changing to $OJDBC
      rm -f $OJDBCLIB
      ln -s $OJDBC $OJDBCLIB
   fi
fi


exit 0
