#!/usr/bin/env perl

use DBI;
use Config::IniFiles;
use strict;

# batchmonconfig.ini file format:
# [Batch Count]
# threshold=400
# trigger = 15
#
#  where threshold = number of queued jobs
#  trigger = number of consecutive samples that threshold is exceeded
#
# [Long Running]
# base=10
# multiplier=0.1
#
## Where base is base number of minutes for over threshold jobs
## Threshold for sum of overtime for long running jobs over the last hour = (base + ( multiplier x number of overtime jobs))



# for PaaS, Connection string format:
# 'Server=tcp:MYDATABASE.database.windows.net,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'
# for IaaS, Connection String Format:
# 'Server=tcp:10.123.25.22,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Connection Timeout=30;'


my $OpenNMSHome = "/home/opennms";
my $configFile = "${OpenNMSHome}/etc/batchmonconfig.ini";
my $overThreshCountFile = "${OpenNMSHome}/var/batchmonoverthreshcount";

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


die "get_ellipsebatchcnt_SQLServer.pl wrong num of args ERR |" if ($#ARGV != 4);

my ($connString, $dbSID, $tableName, $node, $user) = @ARGV;
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

my $dbh = DBI->connect("dbi:ODBC:DRIVER={ODBC Driver 17 for SQL Server};$connString");


die "get_ellipsebatchcnt_SQLServer.pl can not connect to db ERR |" if ( ! $dbh );

my $arraySelect = $dbh->prepare("select count(*) from $tableName") or die "get_ellipsebatchcnt_SQLServer.pl $! ERR |";

$arraySelect->execute();
my ($count) = $arraySelect->fetchrow_array();
$arraySelect->finish();

$arraySelect= $dbh->prepare("select count(*) from $tableName where process_status = 'E'") or die "get_ellipsebatchcnt_SQLServer.pl $! ERR |";

$arraySelect->execute();
my ($execcount) = $arraySelect->fetchrow_array();
$arraySelect->finish();

$arraySelect= $dbh->prepare("select count(*) from $tableName where process_status IN ('N','Q')") or die "get_ellipsebatchcnt_SQLServer.pl $! ERR |";

$arraySelect->execute();
my ($queued) = $arraySelect->fetchrow_array();

$arraySelect->finish();


$arraySelect= $dbh->prepare("select count(*) as Number_Of_Failed_Jobs
from ellipse.msf080 b
where b.process_status = 'F'
and convert(datetime,substring(b.start_date,1,4) + '-' + substring(b.start_date,5,2) + '-' + substring(b.start_date,7,2)
             + ' ' + substring(b.start_time,1,2) + ':' + substring(b.start_time,3,2) +  ':00',120)
    > dateadd(mi,-15,getdate())
") or die "get_ellipsebatchcnt.pl $! ERR |";

$arraySelect->execute();
my ($failed) = $arraySelect->fetchrow_array();
$arraySelect->finish();


my $runningJobsSelect = <<END;
with jobs as
(
select -- Jobs still running
       msf080.prog_name, MSF080.dstrct_code, start_date, start_time+'00' as Start_Time_hhmmss, process_Status,
         DATEDIFF(minute,substring(START_DATE,1,4)+'-'+substring(START_DATE,5,2)+'-'+substring(START_DATE,7,2)+' '+substring(START_TIME,1,2)+':'+substring(START_TIME,3,2)+':00',GETDATE()) as Elapsed_Minutes,
       MSF080.UUID
from ellipse.MSF080
where process_Status = 'E'
UNION ALL
select -- Jobs completed within the last hour
       MSF085.prog_name, MSF085.dstrct_code, stop_date, stop_time_hhmmss, 'C' as process_status,
         DATEDIFF(minute,substring(START_DATE,1,4)+'-'+substring(START_DATE,5,2)+'-'+substring(START_DATE,7,2)+' '+substring(START_TIME_hhmmss,1,2)+':'+substring(START_TIME_hhmmss,3,2)+':'+substring(start_time_hhmmss,5,2),
                         substring(STOP_DATE ,1,4)+'-'+substring(STOP_DATE ,5,2)+'-'+substring(STOP_DATE ,7,2)+' '+substring(STOP_TIME_hhmmss, 1,2)+':'+substring(STOP_TIME_hhmmss, 3,2)+':'+substring(stop_time_hhmmss, 5,2)) as Elapsed_Minutes,
       task_UUID
from ellipse.MSF085 
where datediff(minute,substring(STOP_DATE ,1,4)+'-'+substring(STOP_DATE ,5,2)+'-'+substring(STOP_DATE ,7,2)+' '+substring(STOP_TIME_hhmmss, 1,2)+':'+substring(STOP_TIME_hhmmss, 3,2)+':'+substring(stop_time_hhmmss, 5,2),
                      getdate()) < 30  
)
,
history as -- the history from MSF085
(
select  prog_name,
        dstrct_code,
        --round(sum(elapsed_minutes),5) as Elapsed_Minutes,
        --count(*) as Count_Instances,        
        round(avg(elapsed_minutes),5) as Average_Elapsed,
        --round(median(elapsed_minutes),5) as Median_Elapsed,  -------- MS SQL doesn't support median
        round(stdevp(elapsed_minutes),5) as Std_Deviation    
from (        
        select  prog_name,
                dstrct_code,
                DATEDIFF(minute,substring(START_DATE,1,4)+'-'+substring(START_DATE,5,2)+'-'+substring(START_DATE,7,2)+' '+substring(START_TIME_hhmmss,1,2)+':'+substring(START_TIME_hhmmss,3,2)+':'+substring(start_time_hhmmss,5,2),
                         substring(STOP_DATE ,1,4)+'-'+substring(STOP_DATE ,5,2)+'-'+substring(STOP_DATE ,7,2)+' '+substring(STOP_TIME_hhmmss, 1,2)+':'+substring(STOP_TIME_hhmmss, 3,2)+':'+substring(stop_time_hhmmss, 5,2)) as Elapsed_Minutes
        from    ellipse.msf085
      ) Flat_history
group by prog_name, dstrct_code
)
select sum(Overdue) over() as Total_Overdue, count (Prog_Name) over() as Total_Count
from(
        select Prog_name, dstrct_code, Process_Status, Overdue, uuid
        from (
              select Jobs.prog_name, Jobs.dstrct_code, Jobs.Process_Status,
                     Jobs.elapsed_minutes, History.Average_elapsed+4*History.std_deviation as Threshold,
                     Jobs.Elapsed_Minutes - (History.Average_elapsed+4*History.std_deviation) As OverDue,
                     jobs.uuid
              from jobs inner join history on (history.prog_name = jobs.prog_name and history.dstrct_code = jobs.dstrct_code)
             ) as Raw_Jobs 
        where Overdue > 0 ----- This should be >0. Set to -2 minutes to get test data 
)
END

$arraySelect= $dbh->prepare($runningJobsSelect) or die "get_ellipsebatchcnt.pl $! ERR |";

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

system "date >> $OpenNMSHome/logs/get_ellipsebatchcnt_SQLServer.log";
system "echo -n \"curBatchCnt=${count} \" >> $OpenNMSHome/logs/get_ellipsebatchcnt_SQLServer.log";
system "echo -n \"batchfailures=${failed} \" >> $OpenNMSHome/logs/get_ellipsebatchcnt.log";


exit 0;


