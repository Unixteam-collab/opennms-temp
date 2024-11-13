##############################################################################
##
##  Oracle_force_logging.sh - Oracle DB Force Logging Monitoring 
##
##  Author: Maurice Reardon, JUL-2023
##
##  Brief:  Installed on OpenNMS collector :-
##
##    This script checks for DB not in Force Logging mode (override with threshold
##    defined in abbmon.zen_tab_1hr) 
##
##  Parameters:
##             $1 = OpenNMS node (hostname_DBname)
##             $2 = Target DB user
##             $3 = Target DB pass
##             $4 = ORACLE_SID of DB being monitored
##
##  eg.
##    Oracle_force_logging.sh server_DB abbmon pass DB
##
##
##  Dependencies:-
##
##############################################################################

# -- Start Functions

Check_shell_cmd ()  {

# Normally this script will be run through cron with the full path name
# If it is run manually ensure the full path is used and a SID is passed

   if [ "$SCRIPT" = "Oracle_force_logging.sh" ] || [ "$SCRIPT" = "./Oracle_force_logging.sh" ] ; then
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

   Send_alert

   Finish_up

}

Set_environment ()  {

   ORACLE_HOME=`find /oracle/product/ -maxdepth 1|grep 12.|sort|tail -1`
   PATH=$ORACLE_HOME/bin:$PATH
   export ORACLE_HOME PATH
   LD_LIBRARY_PATH=$(dirname $(find -L /oracle -name libclntsh.so | grep 12. 2> /dev/null))
   export LD_LIBRARY_PATH

}

Run_query ()  {

   # Query the database to check DB Force Logging mode 

      ALERT=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
      set heading off trimspool on serverout on feedback off
      select value1 - threshold from zen_tab_1hr where name='force_logging';
      exit;
EOF`
}

Send_alert () {
      if [ $ALERT -gt 0 ] ; then  
      	/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/oracle/Major -n $TARGETDEVICEID -d "DB not in Force Logging mode" -p "value $ALERT" -p "description DB not in Force Logging mode"
      	return 1
      else
	return 0
      fi
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

# We really only want to run this script once every hour instead of every 10 minutes.
# If the minute part of the time is in the first 10 minutes of the hour, run it, else don't.
# The script by default runs on the 6 minutes (6,16,26,36,46,56).

MIN=`date +%M`
if [ $MIN -le 10 ]
then
   Main
else
   exit 0
fi


