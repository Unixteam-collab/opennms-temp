##############################################################################
##
##  Oracle_EVENT_STAGING_WP.sh - EVENT_STAGING OpenNMS DB Monitoring (customised for Western Power)
##
##  Author: Maurice Reardon, AUG-2024
##
##  Brief:  Installed on OpenNMS collector :-
##
##    This script records 10 minute interval volumes of undelivered EVENT_STAGING records
##
##  Parameters:
##             $1 = OpenNMS node (hostname_DBname)
##             $2 = Target DB user
##             $3 = Target DB pass
##             $4 = ORACLE_SID of DB being monitored
##
##  eg.
##    Oracle_EVENT_STAGING_WP.sh server_DB device_ID abbmon pass DB
##
##
##  Dependencies:-
##
##  The abbmon user requires SELECT priv on the following Ellipse tables:
##  EVENT_STAGING
##
##############################################################################

# -- Start Functions

Check_shell_cmd ()  {

# Normally this script will be run through cron with the full path name
# If it is run manually ensure the full path is used and a SID is passed

   if [ "$SCRIPT" = "Oracle_EVENT_STAGING_WP.sh" ] || [ "$SCRIPT" = "./Oracle_EVENT_STAGING_WP.sh" ] ; then
      echo "Exiting, Use full pathname when running this script!"
      return 1
   fi
   if [ "$ORACLE_SID" = "" ] ; then
      echo "Exiting, no instance passed!"
      return 1
   else
      export ORACLE_SID
   fi
}

Main () {

   HERE=`dirname $SCRIPT` ;  INSTALLDIR=`dirname $HERE`

   Set_environment        # Set Parameters and Oracle environment variables
   if [ "$?" != "0" ] ; then
      Finish_up
   fi

   Run_query

   Finish_up

}

Set_environment ()  {

   ORACLE_HOME=`find /oracle/product/ -maxdepth 1|grep 12.|sort|tail -1`
   PATH=$PATH:$ORACLE_HOME/bin
   export ORACLE_HOME PATH

}

Run_query ()  {

   # Query the database and record the count

sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
set heading off trimspool on serverout on feedback off
insert into abbmon.rowcount select 'ELLIPSE','EVENT_STAGING',sysdate,count(*) from ellipse.event_staging where delivered='N';
commit;
exit
EOF

}

Finish_up ()  {
   exit
}

# --- End functions ---

SCRIPT=$0
OPENNMS_NODE=$1         # Full OpenNMS Node name for the monitored DB
TARGETDEVICEID=$(/opt/opennms/scripts/getNodeID.sh $OPENNMS_NODE)
USER=$2                 # DB user to connect to monitored DB
PASS=$3                 # DB pass to connect to monitored DB
ORACLE_SID=$4          # Oracle SID of monitored DB

Check_shell_cmd        # Validate script command used and SID passed
if [ "$?" != "0" ]
then
   exit
fi

Main


