#!/usr/bin/env perl

use DBI;
use strict;


# for PaaS, Connection string format:
# 'Server=tcp:MYDATABASE.database.windows.net,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'
# for IaaS, Connection String Format:
# 'Server=tcp:10.123.25.22,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Connection Timeout=30;'


my $OpenNMSHome = "/home/opennms";

die "Wrong arguements: Check4StatsGeneration.pl connString nodeName dbName defaultThreshold " if ($#ARGV != 3);

my ($connString, $node, $dbSID, $defaultThreshold) = @ARGV;

my %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );
my %statsThreshHash;
my %priorityHash;
#my $statsThreshodTable=$node . $dbSID.statsthresh;

#open STATSTHRESHTABLE, "<$OpenNMSHome/etc/$statsThresholdTable";
#while ( $_ = <STATSTHRESHTABLE> ){
#    chomp $_;
#    my ($ServName, $DbName,$ObjName,StatsName,$ObjType,$severity,$threshold) = split(",",$_);
#    if ( $severity > 0 && $severity < 4 ) {
#        $priorityHash{$ServName,$DbName,$ObjName,StatsName,$ObjType} = $sevToLoggerStringHash{$severity};
#    }
#    $statsThreshHash{$ServName,$DbName,$ObjName,StatsName,$ObjType} = $threshold;
#}
#close STATSTHRESHTABLE;



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

die "Check4StatsGeneration.pl can not connect to db ERR |" if ( ! $dbh );


my $arraySelect = $dbh->prepare("
sp_MSforeachdb 'USE [\?]; 
 IF DB_ID(''\?'') > 4
BEGIN
SELECT \@\@SERVERNAME As ServerName
      ,''\?'' As DatabaseName 
      ,OBJECT_NAME(s.object_id) AS ObjectName
      ,s.name AS StatisticName
      ,o.type_desc AS ObjectType
      ,STATS_DATE(s.object_id, stats_id) AS StatisticUpdateDate
      ,DATEDIFF(day, STATS_DATE(s.object_id, stats_id), getdate()) StatisticLastUpdateDays
FROM sys.stats s INNER JOIN sys.objects o ON (s.[object_id] = o.[object_id])
WHERE o.[type] not in (''S'', ''IT'')
ORDER BY 3 DESC
END'
") or die "Check4IndexFragmentation.pl $! ERR |";

my $errorMsg = '';
my $errSev = 'warn';  #maps to a p3
my $overThreshCount=0;

print "about to execute\n";
$arraySelect->execute();
while (my ($ServerName, $DatabaseName,$ObjectName,$StatisticName,$ObjectType,$UpdateDate,$LastUpdateDays) = $arraySelect->fetchrow_array()) {


    my $statThresh = $defaultThreshold;
    $ServerName =~ s/\s+$//;
    $DatabaseName =~ s/\s+$//;
    $ObjectName =~ s/\s+$//;
    $StatisticName =~ s/\s+$//;
    $ObjectType =~ s/\s+$//;

    if ( exists $statsThreshHash{$ServerName,$DatabaseName,$ObjectName,$StatisticName,$ObjectType} ) {
        $statThresh = $statsThreshHash{$ServerName,$DatabaseName,$ObjectName,$StatisticName,$ObjectType};
    }
    if ( exists $priorityHash{$ServerName,$DatabaseName,$ObjectName,$StatisticName,$ObjectType} ) {
        $errSev = $priorityHash{$ServerName,$DatabaseName,$ObjectName,$StatisticName,$ObjectType};
    }

   next if ($LastUpdateDays < $statThresh);

   $overThreshCount++;

   $errorMsg .= sprintf( "Object %s/%s in database %s_%s has not had statics generated for %d days.\n", $ObjectName,$StatisticName, $ServerName, $DatabaseName, $LastUpdateDays);

   
}
$arraySelect->finish();

$dbh->disconnect();

if ( $overThreshCount > 0 ) {
   my $resourceID = $dbSID.":AgedStatGeneration";
   $resourceID =~ s/\s+//g;
   system "send-event.pl uei.opennms.org/ABBCS/MSSQL/failure-$errSev -n $nodeid -d \"SQLServer\" -p \"label IndexFrag\" -p \"resourceId $resourceID\" -p \"ds StatsGeneration\" -p \"description $errorMsg.\" ";

}
exit 0;


