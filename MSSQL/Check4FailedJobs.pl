#!/usr/bin/env perl

use DBI;
use strict;


# for PaaS, Connection string format:
# 'Server=tcp:MYDATABASE.database.windows.net,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'
# for IaaS, Connection String Format:
# 'Server=tcp:10.123.25.22,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Connection Timeout=30;'


my $OpenNMSHome = "/home/opennms";

die "Wrong arguements: Check4FailedJobs.pl connString nodeName dbName" if ($#ARGV != 2);

my ($connString, $node, $dbSID) = @ARGV;

my %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );
#my %fragThreshHash;
#my %priorityHash;

#open FRAGTHRESHTABLE, "<$OpenNMSHome/etc/$fragThresholdTable";
#while ( $_ = <FRAGTHRESHTABLE> ){
#    chomp $_;
#    my ($tabName,$indexName,$fragThresh,$severity) = split(",",$_);
#    if ( $severity > 0 && $severity < 4 ) {
#	$priorityHash{$tabName,$indexName} = $sevToLoggerStringHash{$severity};
#    }
#    $fragThreshHash{$tabName,$indexName} = $fragThresh;
#}
#close FRAGTHRESHTABLE;



my $errSev = $sevToLoggerStringHash{3};

my $nodeid;

if ($node =~ /^\d+?$/) {
  $nodeid = $node;
} else {
  my $nodeIP=qx { /opt/opennms/scripts/getNodeIP.sh $node};
  chomp $nodeIP;
  $nodeid=qx { /opt/opennms/scripts/getNodeID.sh $node};
  chomp $nodeid;
}


my $dbh = DBI->connect("dbi:ODBC:DRIVER={ODBC Driver 17 for SQL Server};$connString");

die "Check4FailedJos.pl can not connect to db ERR |" if ( ! $dbh );


my $arraySelect = $dbh->prepare("
DECLARE \@PreviousDate datetime  
DECLARE \@Year VARCHAR(4)   
DECLARE \@Month VARCHAR(2)  
DECLARE \@MonthPre VARCHAR(2)  
DECLARE \@Day VARCHAR(2)  
DECLARE \@DayPre VARCHAR(2)  
DECLARE \@FinalDate INT  
 
SET \@PreviousDate = DATEADD(dd, -1, GETDATE()) -- Last 24 hours   
SET \@Year = DATEPART(yyyy, \@PreviousDate)   
SELECT \@MonthPre = CONVERT(VARCHAR(2), DATEPART(mm, \@PreviousDate))  
SELECT \@Month = RIGHT(CONVERT(VARCHAR, (\@MonthPre + 1000000000)),2)  
SELECT \@DayPre = CONVERT(VARCHAR(2), DATEPART(dd, \@PreviousDate))  
SELECT \@Day = RIGHT(CONVERT(VARCHAR, (\@DayPre + 1000000000)),2)  
SET \@FinalDate = CAST(\@Year + \@Month + \@Day AS INT)  

SELECT   j.[name],  
         s.step_name,  
         h.step_id,  
         h.step_name,  
         h.run_date,  
         h.run_time,  
         h.sql_severity,  
         h.message,   
         h.server  
FROM     msdb.dbo.sysjobhistory h  
         INNER JOIN msdb.dbo.sysjobs j  
           ON h.job_id = j.job_id  
         INNER JOIN msdb.dbo.sysjobsteps s  
           ON j.job_id = s.job_id 
           AND h.step_id = s.step_id  
WHERE    h.run_status = 0 --Failed jobs  
         AND h.run_date > \@FinalDate  
ORDER BY h.instance_id DESC  
") or die "Check4cwFailedJobs.pl $! ERR |";

print "about to execute\n";
$arraySelect->execute();
while (my ($JobName,$SStepName,$StepID,$HStepName,$RunDate,$RunTime,$SQL_severity,$Message,$Server) = $arraySelect->fetchrow_array()) {

    my $errSev = 'warn';  #maps to a p3

#   print "JobName: $JobName\n";
#   print "SStep: $SStepName\n";
#   print "StepID: $StepID\n";
#   print "HStepName: $HStepName\n";
#   print "RunDate: $RunDate\n";
#   print "RunTime: $RunTime\n";
#   print "SQL_severity: $SQL_severity\n";
#   print "Message: $Message\n";
#   print "Server: $Server\n";

print "Nodeid: $nodeid\n";
   my $errorMsg = sprintf( "Failed SQL Server Job %s on Server %s. Message: %s", $JobName, $Server, substr($Message,0,200));
   my $resourceID = $node.":".$RunDate.":".$RunTime;
   $resourceID =~ s/\s+//g;
   system "send-event.pl uei.opennms.org/ABBCS/MSSQL/failure-$errSev -n $nodeid -d \"SQLServer\" -p \"label FailedJobs\" -p \"resourceId $resourceID\" -p \"ds FailedJobs\" -p \'description $errorMsg.\' ";


   
}
$arraySelect->finish();

$dbh->disconnect();

exit 0;
