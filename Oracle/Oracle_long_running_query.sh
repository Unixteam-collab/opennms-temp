##############################################################################
##
##  Oracle_long_running_query.sh - Oracle DB long running query Monitoring 
##
##  Author: Maurice Reardon, FEB-2020
##
##  Brief:  Installed on OpenNMS collector :-
##
##    This script checks for long running queries (longer than threshold
##    defined in abbmon.zen_tab_5min) 
##
##  Parameters:
##             $1 = OpenNMS node (hostname_DBname)
##             $2 = Target DB user
##             $3 = Target DB pass
##             $4 = ORACLE_SID of DB being monitored
##
##  eg.
##    Oracle_long_running_query.sh server_DB abbmon pass DB
##
##
##  Dependencies:-
##
##############################################################################

# -- Start Functions

Check_shell_cmd ()  {

# Normally this script will be run through cron with the full path name
# If it is run manually ensure the full path is used and a SID is passed

   if [ "$SCRIPT" = "Oracle_long_running_query.sh" ] || [ "$SCRIPT" = "./Oracle_long_running_query.sh" ] ; then
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

   # Query the database to check for any long running queries

      ALERT=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
      set heading off trimspool on serverout on feedback off
SELECT distinct('Minutes='
||trim(trunc(to_char((sysdate-a.start_time)*1440)))
||'  SID='
||a.sid
||'  USER='
||trim(a.username)
||'  Start='
||trim(to_char(a.start_time,'hh24.mi.ss'))
||'  '
||trim(a.message)
||'  Percent_Done='
||trim(trunc(to_char((a.sofar/a.totalwork)*100)))
||' SQL_HASH_VALUE='
||trim(to_char(a.sql_hash_value)))    
FROM v\\$session_longops a, v\\$session b
WHERE a.username not in ('RMAN','SYS')  
and decode(a.sofar,0,1,a.sofar)/decode(a.totalwork,0,1,a.totalwork) < 1 
and (sysdate-a.start_time)*1440 > (select threshold from zen_tab_5min 
where name='long_running_query') 
and sysdate-a.start_time = (select max(sysdate-start_time) 
from v\\$session_longops 
WHERE username not in ('RMAN','SYS')   
and decode(sofar,0,1,sofar)/decode(totalwork,0,1,totalwork) < 1 
and (sysdate-start_time)*1440 > (select threshold from zen_tab_5min where name='long_running_query'))
and a.sid||a.serial# = b.sid||b.serial#
and b.status='ACTIVE'
and b.program||b.username != 'JDBC Thin ClientELLIPSE';
exit;
EOF`
}

Send_alert () {
      if [ ${#ALERT} -gt 0 ] ; then   # Test length of sqlplus result
      	/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/oracle/Major -n $TARGETDEVICEID -d "Long Running Query" -p "value $ALERT" -p "description Long Running Query"
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

