#!/bin/ksh
##############################################################################
##
##  Oracle_check_DRlag.sh - Oracle DB DR OpenNMS Monitoring Script
##
##  Author: Maurice Reardon, 2017
##
##  Brief:  Installed on OpenNMS DR collector :-
##
##    This script checks the DR DB replication is not lagged behind
##    the Primary database.
##    Works with either Dataguard or ORADR.
##
##  Parameters:
##             $1 = OpenNMS node (hostname_DBname)
##             $2 = Target DB user
##             $3 = Target DB pass
##             $4 = Maximum permitted lag threshold in minutes
##             $5 = ORACLE_SID of DR DB being monitored
##
##  eg.  Oracle_check_DRlag.sh oct-evad01-dbs-ora01_octelprd user pass 60 octelprd
##
##
##  Dependencies:-
##
##############################################################################

# -- Start Functions

Check_shell_cmd ()  {

# Normally this script will be run through cron with the full path name
# If it is run manually ensure the full path is used and a SID is passed

   if [ "$SCRIPT" = "Oracle_check_DRlag.sh" ] || [ "$SCRIPT" = "./Oracle_check_DRlag.sh" ] ; then
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

   Check_lag

   Finish_up

}

Set_environment ()  {

   ORACLE_HOME=`find /oracle/product/ -maxdepth 1|grep 12.|sort|tail -1`
   PATH=$PATH:$ORACLE_HOME/bin
   export ORACLE_HOME PATH

}

Run_query ()  {

   # Query the database to determine time lag

   TRIES=1
   while test $TRIES != 6
   do
      LAGGED=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE as sysdba" <<EOF
      set heading off trimspool on serverout on feedback off
        select distinct(
        case when database_role != 'PRIMARY'
        then
            (select (substr(value,2,2)*1440)+(substr(value,5,2)*60)+(substr(value,8,2))
             from v\\$dataguard_stats where name = 'apply lag')
        else
            (select trunc(((select sysdate from dual) - (select max(first_time)
             from v\\$log_history)) * 1440) - 10
                 from dual)
        end)
        from v\\$database;
        exit;
EOF`
      if [ ${#LAGGED} -gt 24 ] ; then   # Test length of sqlplus result
         sleep 60                       # eg. ORADR DB down for roll-forward
         TRIES=`expr $TRIES + 1`
      else
         return 0
      fi
   done

   if [ "$TRIES" = "6" ] ; then
      return 1
   fi
}

Check_lag () {
   # Compare current DR lag minutes to max permitted threshold, alert if lagged
   if [ "$LAGGED" -gt "$LAG" ] ; then
      /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/jdbc/oracle/DRlag-trigger -n $TARGETDEVICEID -d "DR Database Lag" -p "value $LAGGED" -p "resourceId DRlag" -p "ds DRlag" -p "description DR Database Lag exceeds threshold"
      return 1
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
LAG=$4                 # Maximum permitted DR lag threshold
ORACLE_SID=$5           # Oracle SID of monitored DB

Check_shell_cmd        # Validate script command used and SID passed
if [ "$?" != "0" ]
then
   exit
fi

Main

