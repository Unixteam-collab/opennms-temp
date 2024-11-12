#!/usr/bin/env perl

#
# Monitors for when the sum of the Overdue time for batch jobs overdue in the past hour exceeds a threshold
#   Threshold is calculated as BASE + ( number of overthreshold jobs x multiplier) 
#      Setting the multiplier to 0 will always use BASE as the threshold.  a value greater than 0 will increase
#      the threshold by a factor dependant on the number of jobs that are currently over their threshold.
# parameters: DB
#             NODE
#             BASE  - base threshold amount
#             multiplier - value to multiply count of over threshold jobs to add to base for sum of over due time.
#             DBUSER
#             DBPASS 
# example: check_ellipsebatch_longrun_SQLServer_watch.pl $DB $NODE 10 1.1  $DBUSER $DBPASSWD



use DBI;
use strict;


my $OpenNMSHome = "/home/opennms";
#my $errSev="crit";
my $errSev="warn";


die "Wrong arguements: check_ellipsebatch_longrun_SQLServer_watch.pl connString nodeName base multiplier " if ($#ARGV != 2);

my ($connString, $nodeName, $BASE, $MULTIPLIER ) = @ARGV;

my $thresholdFile="$OpenNMSHome/etc/" . $nodeName . ".threshold";
my $targetDeviceId=qx { /opt/opennms/scripts/getNodeID.sh $nodeName};
chomp $targetDeviceId;

my %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );

my %progSevHash;

my %thresholdHash;
open THRESHOLDFILE, "<$thresholdFile";
while ( $_ = <THRESHOLDFILE> ){
    chomp $_;
    my ($progName,$threshold,$severity) = split(",",$_);
    $thresholdHash{$progName} = $threshold;
    if ( $severity > 0 && $severity < 4 ) {
        $progSevHash{$progName} = $sevToLoggerStringHash{$severity};
    }
}
close THRESHOLDFILE;

my $dbh = DBI->connect("dbi:ODBC:DRIVER={ODBC Driver 17 for SQL Server};$connString");

if ( ! $dbh  ) {
    printf "check_ellipsebatch_logrun_SQLServer_watch.pl ERR \| longrun_count=0;;;;\n";
    exit 1;
}

my $overDueBatchSelect = <<END;
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
                      getdate()) < 60
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
select * from (
select Prog_Name, Dstrct_code, UUID, Process_Status, elapsed, Threshold, Overdue, sum(Overdue) over() as Total_Overdue, count(Prog_Name) over() as Total_count
from(
        select Prog_name, dstrct_code, Process_Status, elapsed, Threshold, Overdue, uuid
        from (
              select Jobs.prog_name, Jobs.dstrct_code, Jobs.Process_Status,
                     Jobs.elapsed_minutes as elapsed, History.Average_elapsed+4*History.std_deviation as Threshold,
                     Jobs.Elapsed_Minutes - (History.Average_elapsed+4*History.std_deviation) As OverDue,
                     jobs.uuid
              from jobs inner join history on (history.prog_name = jobs.prog_name and history.dstrct_code = jobs.dstrct_code)
             ) as Raw_Jobs 
        where Overdue > 0 ----- This should be >0. Set to -2 minutes to get test data 
) as Summed_Jobs ) as Over_Jobs
where Total_OverDue > 10 ----- This should be set to 10 minutes

END

my $arraySelect = $dbh->prepare($overDueBatchSelect) or die $!;
#my $longRunCount = 0;
my $PROGLIST = "Prog_name   District_code  Status     Runtime   Threshold   Overdue by";


$arraySelect->execute();
my $GOT_DATA=0;
while ( my ($prog_name, $district_code, $uuid, $status, $runtime_minutes, $threshold, $overdue, $TotalOverdue, $Count) = $arraySelect->fetchrow_array() ) {
    #printf "%s %s %s %d %d %d\n", $prog_name, $uuid, $district_code, $runtime_minutes, $priorCount, $threshold;
    $prog_name =~ s/\s+$//;
    $GOT_DATA=1;

    my $weightedthreshold=$BASE+($Count*$MULTIPLIER);
    if ( $TotalOverdue > $weightedthreshold ) {
        
       $PROGLIST=sprintf "%s\n%-11s %-14s   %-5s %10.1f  %10.1f  %10.1f", $PROGLIST, $prog_name, $district_code, $status, $runtime_minutes, $threshold, $overdue;
   }

}
$arraySelect->finish();

if ( $GOT_DATA == 1 ) {
  printf "$PROGLIST\n";
  system "send-event.pl uei.opennms.org/ABBCS/Batch/failure-$errSev -n $targetDeviceId -d \"Batch failure\" -p \"label Batch\" -p \"resourceId EllipseBatchLongRunning\" -p \"ds batchLongrun\" -p \"description Excessive long running jobs\n$PROGLIST.\" ";
}


$dbh->disconnect();

#printf "check_ellipsebatch_longrun.pl OK | longrun_count=$longRunCount;;;;\n";

exit 0;

