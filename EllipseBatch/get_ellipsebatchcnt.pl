#!/usr/bin/env perl

use DBD::Oracle;
use Config::IniFiles;

use strict;

# batchmonconfig.ini file format:
# [Batch Count]
# threshold=400
# trigger = 15
#
##  where threshold = number of queued jobs
##  trigger = number of consecutive samples that threshold is exceeded
#
# [Long Running]
# base=10
# multiplier=0.1
#
## Where base is base number of minutes for over threshold jobs
## Threshold for sum of overtime for long running jobs over the last hour = (base + ( multiplier x number of overtime jobs))
 


my $oraHome = `dirname \$\(find /oracle -name oraInst.loc 2> /dev/null\)`;
chomp $oraHome;
$oraHome =~ s/\s+$//;
my $oraBase = "/oracle";

my $OpenNMSHome = "/home/opennms";
my $configFile = "${OpenNMSHome}/etc/batchmonconfig.ini";
my $overThreshCountFile = "${OpenNMSHome}/var/batchmonoverthreshcount";



$ENV{'TNS_ADMIN'}="${oraHome}/network/admin";
$ENV{'ORACLE_BASE'}=$oraBase;
$ENV{'ORACLE_HOME'}=$oraHome;

my $curPath = $ENV{'PATH'};
$curPath = $curPath . ":" . "${oraHome}/bin";
$ENV{'PATH'} = $curPath;

my $oraLdLibPath = "${oraHome}/lib";
my $ldLibPath = $ENV{'LD_LIBRARY_PATH'};
if ( defined $ldLibPath && $ldLibPath ne '' )  {
    $ldLibPath = $ldLibPath . ":" . $oraLdLibPath;
} else {
    $ldLibPath = $oraLdLibPath;
}

my $q_trigger = 1;
my $q_threshold = 999999999999999;
my $lr_base = 10;
my $lr_multiplier = 0.1;

if ( -f $configFile )
{
   my $ini = Config::IniFiles->new(-file => $configFile);

   $q_threshold = $ini->val( 'Batch Count', 'threshold' );
   $q_trigger = $ini->val( 'Batch Count', 'trigger' );
   $lr_base = $ini->val( 'Long Running', 'base');
   $lr_multiplier = $ini->val( 'Long Running', 'multiplier');
} 
my $q_overThreshCount = 0;
if ( -f $overThreshCountFile )
{
   open OVERTHRESHCOUNTFILE, "$overThreshCountFile";
   $q_overThreshCount = <OVERTHRESHCOUNTFILE>;
   close OVERTHRESHCOUNTFILE;
}


die "get_ellipsebatchcnt.pl wrong num of args ERR |" if ($#ARGV != 4);

#./get_ellipsebatchcnt.pl eau-evap01-dbs-ora01.eauelprd ellipse.msf080 abbmon abbmon 31
#ellprddb1_ellprd, ellipse.msf085, zenoss, zenoss
my ($dbSID, $tableName, $user, $passwd, $node) = @ARGV;
my $nodeid;

if ($node =~ /^\d+?$/) {
  $nodeid = $node;
} else {
  my $nodeIP=qx { /opt/opennms/scripts/getNodeIP.sh $node};
  chomp $nodeIP;
  $nodeid=qx { /opt/opennms/scripts/getNodeID.sh $node};
  chomp $nodeid;

  my $UPDATES=qx { /opt/opennms/scripts/ons_add_service.sh Servers $node $nodeIP ABBCS-EllipseBatch};

  if ( $UPDATES =~ /true/ ) {
     system "/opt/opennms/bin/provision.pl requisition import Servers";
  }
}

# get the prior value for same sid/tablename/user
my $priorStateFilename = join( '-', ($dbSID, $tableName, $user));
$priorStateFilename = "$OpenNMSHome/var/ellipsebatchcnt-" . $priorStateFilename;
open PRIORSTATEFILE, "<$priorStateFilename";
my $priorEllipseBatchCnt = <PRIORSTATEFILE>;
close PRIORSTATEFILE;

my $dbh = DBI->connect("dbi:Oracle:$dbSID", $user, $passwd, {AutoCommit => 0 });

die "get_ellipsebatchcnt.pl can not connect to db ERR |" if ( ! $dbh );

my $arraySelect = $dbh->prepare("select count(*) from $tableName") or die "get_ellipsebatchcnt.pl $! ERR |";

$arraySelect->execute();
my ($count) = $arraySelect->fetchrow_array();
$arraySelect->finish();

$arraySelect= $dbh->prepare("select count(*) from $tableName where process_status = 'E'") or die "get_ellipsebatchcnt.pl $! ERR |";

$arraySelect->execute();
my ($execcount) = $arraySelect->fetchrow_array();
$arraySelect->finish();

$arraySelect= $dbh->prepare("select count(*) from $tableName where process_status IN ('N','Q')") or die "get_ellipsebatchcnt.pl $! ERR |";

$arraySelect->execute();
my ($queued) = $arraySelect->fetchrow_array();
$arraySelect->finish();


$arraySelect= $dbh->prepare("select count(*) Number_Of_Failed_Jobs
from ellipse.msf080 b
inner join ellipse.msf000_dc0002 tz on (tz.dstrct_code = b.dstrct_code)
where b.process_status = 'F'
and to_date(start_date||start_time,'YYYYMMDDHH24MI') 
      > cast(SYSTIMESTAMP at time zone NVL(trim(tz.district_time_zone),sessiontimezone) as date) - 15/(24*60)
") or die "get_ellipsebatchcnt.pl $! ERR |";

$arraySelect->execute();
my ($failed) = $arraySelect->fetchrow_array();
$arraySelect->finish();

$arraySelect= $dbh->prepare("
with jobs as
(
select -- Jobs still running
       msf080.prog_name, MSF080.dstrct_code, start_date, start_time||'00', process_Status,
       round(1440 * (cast(SYSTIMESTAMP at time zone NVL(trim(tz.district_time_zone),sessiontimezone) as date) 
       - to_date(start_date||start_time,'YYYYMMDDHH24MI')),5) as Elapsed_Minutes,
       MSF080.UUID
from ellipse.MSF080
inner join ellipse.MSF000_dc0002 tz on (tz.dstrct_code = MSF080.dstrct_code)
where process_Status = 'E'
UNION ALL
select -- Jobs completed within the last hour
       MSF085.prog_name, MSF085.dstrct_code, stop_date, stop_time_hhmmss, 'C' as process_status,
       round(1440 * (to_date(stop_date||stop_time_hhmmss,'YYYYMMDDHH24MISS') - to_date(start_date||start_time_hhmmss,'YYYYMMDDHH24MISS')),5) as Elapsed_Minutes,
       task_UUID
from ellipse.MSF085 
inner join ellipse.msf000_dc0002 tz on (tz.dstrct_code = MSF085.dstrct_code)
where to_date(stop_date||stop_time_hhmmss,'YYYYMMDDHH24MISS') 
      > cast(SYSTIMESTAMP at time zone NVL(trim(tz.district_time_zone),sessiontimezone) as date) -1/24 -- 1 hour
)
,
history as -- the history from MSF085
(
select  prog_name,
        dstrct_code,
        --round(sum(elapsed_minutes),5) as Elapsed_Minutes,
        --count(*) as Count_Instances,        
        --round(avg(elapsed_minutes),5) as Average_Elapsed,
        round(median(elapsed_minutes),5) as Median_Elapsed,
        round(stddev(elapsed_minutes),5) as Std_Deviation        
from (        
        select  prog_name,
                dstrct_code,
                1440 * (to_date(stop_date||stop_time_hhmmss,'YYYYMMDDHH24MISS') - to_date(start_date||start_time_hhmmss,'YYYYMMDDHH24MISS')) as Elapsed_Minutes
        from    ellipse.msf085
      )
group by prog_name, dstrct_code
)
select sum(Overdue) over() as Total_Overdue, count(Prog_Name) over() as Total_count
from(
        select Prog_name, dstrct_code, Process_Status, elapsed, Threshold, Overdue, uuid
        from (
              select Jobs.prog_name, Jobs.dstrct_code, Jobs.Process_Status,
                     Jobs.elapsed_minutes elapsed, History.median_elapsed+4*History.std_deviation as Threshold,
                     Jobs.Elapsed_Minutes - (History.median_elapsed+4*History.std_deviation) As OverDue,
                     jobs.uuid
              from jobs inner join history on (history.prog_name = jobs.prog_name and history.dstrct_code = jobs.dstrct_code)
             ) 
        where Overdue > 0 ----- This should be >0. Set to -2 minutes to get test data 
)
") or die "get_ellipsebatchcnt.pl $! ERR |";

$arraySelect->execute();
my ($totalOverdue,$totalCount) = $arraySelect->fetchrow_array();
$arraySelect->finish();

if ( (length($totalOverdue) == 0) || ($totalOverdue < 0 ) ) {
    $totalOverdue = 0;
}
if ( (length($totalCount) == 0) || ($totalCount < 0 ) ) {
    $totalCount = 0;
}

$dbh->disconnect();

# now calculate the change from last invocation
my $changeAmount = $count - $priorEllipseBatchCnt;

if ( $changeAmount < 0 ) {
    $changeAmount = 0;
}

if ( $queued > $q_threshold ) {
    $q_overThreshCount = $q_overThreshCount + 1;
} else {
    $q_overThreshCount = 0;
}


#printf "get_ellipsebatchcnt.pl OK | curBatchCnt=${changeAmount};;;;\n";
printf "<ellipse node=\"${nodeid}\">\n";
printf "         <batchcount>${changeAmount}</batchcount>\n";
printf "         <executing>${execcount}</executing>\n";
printf "         <queued>${queued}</queued>\n";
printf "         <qThreshold>${q_threshold}</qThreshold>\n";
printf "         <qThresholdExceeded>${q_overThreshCount}</qThresholdExceeded>\n";
printf "         <qTrigger>${q_trigger}</qTrigger>\n";
printf "         <batchfailures>${failed}</batchfailures>\n";
printf "         <lrTotalOverdue>${totalOverdue}</lrTotalOverdue>\n";
printf "         <lrTotalCount>${totalCount}</lrTotalCount>\n";
printf "         <lrBase>${lr_base}</lrBase>\n";
printf "         <lrMultiplier>${lr_multiplier}</lrMultiplier>\n";
printf "</ellipse>\n";

system "echo $count >$priorStateFilename";
system "echo $q_overThreshCount >$overThreshCountFile";


system "date >> $OpenNMSHome/logs/get_ellipsebatchcnt.log";
system "echo -n \"curBatchCnt=${count} \" >> $OpenNMSHome/logs/get_ellipsebatchcnt.log";
system "echo -n \"batchfailures=${failed} \" >> $OpenNMSHome/logs/get_ellipsebatchcnt.log";

exit 0;


