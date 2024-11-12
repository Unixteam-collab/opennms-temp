##############################################################################
##
##  Oracle_blocking_locks_10g.sh - Oracle DB blocking locks OpenNMS  Monitoring 
##
##  Author: Maurice Reardon, SEP-2022
##
##  Brief:  Installed on OpenNMS collector :-
##
##    This script checks for any blocking locks for duration longer than 
##    threshold in zen_tab_5min 
##
##  Parameters:
##             $1 = OpenNMS node (hostname_DBname)
##             $2 = Target DB user
##             $3 = Target DB pass
##             $4 = ORACLE_SID of DB being monitored
##
##  eg.
##    Oracle_blocking_locks_10g.sh server_DB abbmon pass DB
##
##
##  Dependencies:-
##
##############################################################################

# -- Start Functions

Check_shell_cmd ()  {

# Normally this script will be run through cron with the full path name
# If it is run manually ensure the full path is used and a SID is passed

   if [ "$SCRIPT" = "Oracle_blocking_locks_10g.sh" ] || [ "$SCRIPT" = "./Oracle_blocking_locks_10g.sh" ] ; then
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

   # Query the database to check for any blocking locks

      ALERT=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
      set heading off trimspool on serverout on feedback off
select 'Blocking Lock= '||c.spid||' '||s1.username||'@'||s1.machine||' ('||s1.sid||','||s1.serial#||') blocking 
'||s2.username||'@'||s2.machine||' ('||s2.sid||','||s2.serial#||') - for '||l2.ctime||' seconds'  AS Blocking_Lock
from v\\$lock l1, v\\$session s1, v\\$lock l2, v\\$session s2, v\\$process c
where s1.sid=l1.sid and s2.sid=l2.sid and s1.paddr=c.addr
and l1.BLOCK=1 and l2.request > 0 and l1.id1 = l2.id1 and l1.id2 = l2.id2 and l2.ctime > (select threshold from zen_tab_5min where name='blocking_locks') 
order by l2.ctime desc;      
exit;
EOF`
}

Send_alert () {
      if [ ${#ALERT} -gt 0 ] ; then   # Test length of sqlplus result
      	/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/oracle/Major -n $TARGETDEVICEID -d "Blocking Locks" -p "value $ALERT" -p "description Blocking Locks"
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

