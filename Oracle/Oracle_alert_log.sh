#!/bin/ksh
##############################################################################
##
##  Oracle_alert_log.sh - Oracle DB Alert Log OpenNMS Monitoring Script
##
##  Author: Maurice Reardon, 2017
##
##  Brief:  Installed on OpenNMS collector :-
##
##    This script checks for new Alert Log errors 
##
##  Parameters:
##             $1 = OpenNMS node (hostname_DBname)
##             $2 = Target DB user
##             $3 = Target DB pass
##             $4 = ORACLE_SID of DB being monitored
##
##  eg.
##    Oracle_alert_log.sh oct-evad01-dbs-ora01_octelprd abbmon pass octelprd
##
##
##  Dependencies:-
##
##############################################################################

# -- Start Functions

Check_shell_cmd ()  {

# Normally this script will be run through cron with the full path name
# If it is run manually ensure the full path is used and a SID is passed

   if [ "$SCRIPT" = "Oracle_alert_log.sh" ] || [ "$SCRIPT" = "./Oracle_alert_log.sh" ] ; then
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

   # Query the database to check for any new alerts

      ALERT=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
      set heading off trimspool on serverout on feedback off
      select value from zen_tab_msg; 
      exit;
EOF`

      LEVEL=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
      set heading off trimspool on serverout on feedback off
      select name from zen_tab_msg;
      exit;
EOF`

 
}

Send_alert () {
      if [ ${#ALERT} -gt 8 ] ; then   # Test length of sqlplus result
        if [[ $LEVEL == *"zen_tab_msg_warning"* && $LEVEL != *"zen_tab_msg_alarm"* ]] ; then     # If we have warning but NOT alarm, raise as P3
          /opt/opennms/bin/send-event.pl uei.opennms.org/vendor/ABBCS/oracle/Major -n $TARGETDEVICEID -d "Alert Log error" -p "value $ALERT" -p "description Alert Log error" -x 5
        else                                                                                     # otherwise let the default logic do it's thing (P2)
          /opt/opennms/bin/send-event.pl uei.opennms.org/vendor/ABBCS/oracle/Major -n $TARGETDEVICEID -d "Alert Log error" -p "value $ALERT" -p "description Alert Log error"
        fi
sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
      delete from zen_tab_msg;
      commit;
      exit;
EOF
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

