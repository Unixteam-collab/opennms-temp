##############################################################################
##
##  Oracle_days_without_backup.sh - Oracle DB backup Monitoring 
##
##  Author: Maurice Reardon, JUL-2023
##
##  Brief:  Installed on OpenNMS collector :-
##
##    This script checks for days since last successful backup (longer than threshold
##    defined in abbmon.zen_tab_5min) 
##
##  Parameters:
##             $1 = OpenNMS node (hostname_DBname)
##             $2 = Target DB user
##             $3 = Target DB pass
##             $4 = ORACLE_SID of DB being monitored
##
##  eg.
##    Oracle_days_without_backup.sh server_DB abbmon pass DB
##
##
##  Dependencies:-
##
##############################################################################

# -- Start Functions

Check_shell_cmd ()  {

# Normally this script will be run through cron with the full path name
# If it is run manually ensure the full path is used and a SID is passed

   if [ "$SCRIPT" = "Oracle_days_without_backup.sh" ] || [ "$SCRIPT" = "./Oracle_days_without_backup.sh" ] ; then
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
   PATH=$PATH:$ORACLE_HOME/bin
   export ORACLE_HOME PATH

}

Run_query ()  {

   # Query the database to check how many days since last successful backup 

      ALERT=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
      set heading off trimspool on serverout on feedback off
      select value1 - threshold from zen_tab_5min where name='days_without_backup';
      exit;
EOF`
}

Send_alert () {
      if [ $ALERT -gt 0 ] ; then  
      	/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/oracle/Major -n $TARGETDEVICEID -d "Days Without Backup" -p "value $ALERT" -p "description Days Without Backup"
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

Main

