##############################################################################
##
##  Oracle_space.sh - Oracle DB space monitoring
##
##  Author: Maurice Reardon, JUN-2024
##
##  Brief:  Installed on OpenNMS collector :-
##
##    This script checks for Tablespace used above specific threshold percentage
##
##  Parameters:
##             $1 = OpenNMS node (hostname_DBname)
##             $2 = Target DB user
##             $3 = Target DB pass
##             $4 = ORACLE_SID of DB being monitored
##             $5 = Alarm Threshold percentage used
##             $6 = Warning Threshold percentage used
##
##  eg.
##    Oracle_space.sh server_DB abbmon pass DB alarm warning
##
##
##  Dependencies:-
##
##############################################################################

# -- Start Functions

Check_shell_cmd ()  {

# Normally this script will be run through cron with the full path name
# If it is run manually ensure the full path is used and a SID is passed

   if [ "$SCRIPT" = "Oracle_space.sh" ] || [ "$SCRIPT" = "./Oracle_space.sh" ] ; then
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

   # Query the database to check for any unexpected locked accounts

      ALERT1=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
      set heading off trimspool on serverout on feedback off
alter session set nls_date_format = 'DD-MON-YYYY HH24:MI:SS';
select 'Tablespace '||b.value2||' '||b.value1||'% used  ' from zen_tab_5min b where b.name='tablespace_%used' and b.value1 = (select max(b.value1) from zen_tab_5min where name='tablespace_%used') and b.value1 >= $ALARM;
exit;
EOF`

      ALERT2=`sqlplus -s "$USER/$PASS@$OPENNMS_NODE" <<EOF
      set heading off trimspool on serverout on feedback off
alter session set nls_date_format = 'DD-MON-YYYY HH24:MI:SS';
select 'Tablespace '||b.value2||' '||b.value1||'% used  ' from zen_tab_5min b where b.name='tablespace_%used' and b.value1 = (select max(b.value1) from zen_tab_5min where name='tablespace_%used') and b.value1 >= $WARN;
exit;
EOF`

}

Send_alert () {
      if [ ${#ALERT1} -gt 0 ] ; then   # Test length of sqlplus result
            /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/oracle/Major -n $TARGETDEVICEID -d "Tablespace Used" -p "value $ALERT1" -p "description Tablespace Used"
            return 1
      else
        if [ ${#ALERT2} -gt 0 ] ; then   # Test length of sqlplus result - warning result, raise a P4
            /opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/oracle/Warning -n $TARGETDEVICEID -d "Tablespace Used" -p "value $ALERT2" -p "description Tablespace Used"
            return 1
        else
            return 0
        fi
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
ORACLE_SID=$4           # Oracle SID of monitored DB
ALARM=$5                # Percentage usage above which an alert should be issued
WARN=$6                 # Percentage usage above which a warning should be issued

Check_shell_cmd        # Validate script command used and SID passed
if [ "$?" != "0" ]
then
   exit
fi

Main

