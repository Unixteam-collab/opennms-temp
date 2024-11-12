#!/usr/bin/env perl

use DBI;
use strict;

# note: set negative fragmentation to suppress alerting for specific index

# for PaaS, Connection string format:
# 'Server=tcp:MYDATABASE.database.windows.net,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'
# for IaaS, Connection String Format:
# 'Server=tcp:10.123.25.22,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Connection Timeout=30;'


my $OpenNMSHome = "/home/opennms";

die "Wrong arguements: Check4IndexFragmentation.pl connString nodeName dbName defaultFragThreshold fragThresholdTable" if ($#ARGV != 4);

my ($connString, $node, $dbSID, $fragmentation, $fragThresholdTable) = @ARGV;

my %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );
my %fragThreshHash;
my %priorityHash;

open FRAGTHRESHTABLE, "<$OpenNMSHome/etc/$fragThresholdTable";
while ( $_ = <FRAGTHRESHTABLE> ){
    chomp $_;
    my ($tabName,$indexName,$fragThresh,$severity) = split(",",$_);
    if ( $severity > 0 && $severity < 4 ) {
	$priorityHash{$tabName,$indexName} = $sevToLoggerStringHash{$severity};
    }
    $fragThreshHash{$tabName,$indexName} = $fragThresh;
}
close FRAGTHRESHTABLE;



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

die "Check4IndexFragmentation.pl can not connect to db ERR |" if ( ! $dbh );


my $arraySelect = $dbh->prepare("
   SELECT OBJECT_NAME(ind.OBJECT_ID) AS TableName,
       ind.name AS IndexName,
       indexstats.index_type_desc AS IndexType,
       indexstats.avg_fragmentation_in_percent AS FragPct
   FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, NULL) indexstats
   INNER JOIN sys.indexes ind 
   ON ind.object_id = indexstats.object_id
   AND ind.index_id = indexstats.index_id
   ORDER BY indexstats.avg_fragmentation_in_percent DESC
") or die "Check4IndexFragmentation.pl $! ERR |";

print "about to execute\n";
$arraySelect->execute();
while (my ($TableName,$IndexName,$IndexType,$FragPct) = $arraySelect->fetchrow_array()) {


    my $errSev = 'warn';  #maps to a p3
    my $fragThresh = $fragmentation;
    $TableName =~ s/\s+$//;
    $IndexName =~ s/\s+$//;

    if ( exists $fragThreshHash{$TableName,$IndexName} ) {
        $fragThresh = $fragThreshHash{$TableName,$IndexName};
    }
    if ( exists $priorityHash{$TableName,$IndexName} ) {
        $errSev = $priorityHash{$TableName,$IndexName};
    }

   next if ($IndexName eq '');
   next if ($FragPct <= $fragThresh);
   next if ($fragThresh < 0);

   my $errorMsg = sprintf( "Index %s on table %s exceeds Fragmentation threshold of %d\%.  Current fragmentation percent %8.2f", $IndexName, $TableName, $fragThresh, $FragPct);
   my $resourceID = $dbSID.":".$TableName.":".$IndexName;
   $resourceID =~ s/\s+//g;
   system "send-event.pl uei.opennms.org/ABBCS/MSSQL/failure-$errSev -n $nodeid -d \"SQLServer\" -p \"label IndexFrag\" -p \"resourceId $resourceID\" -p \"ds IndexFrag\" -p \"description $errorMsg.\" ";
   if ( ! exists $fragThreshHash{$TableName,$IndexName} ) {
        open FRAGTHRESHTABLE, ">>$OpenNMSHome/etc/$fragThresholdTable";
        print FRAGTHRESHTABLE "$TableName,$IndexName,$fragThresh,3\n";
        close FRAGTHRESHTABLE;
   }


   
}
$arraySelect->finish();

$dbh->disconnect();

exit 0;


