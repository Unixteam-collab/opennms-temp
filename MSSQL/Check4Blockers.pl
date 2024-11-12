#!/usr/bin/env perl

use DBI;
use strict;


# for PaaS, Connection string format:
# 'Server=tcp:MYDATABASE.database.windows.net,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'
# for IaaS, Connection String Format:
# 'Server=tcp:10.123.25.22,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Connection Timeout=30;'


my $OpenNMSHome = "/home/opennms";

die "Wrong arguements: Check4Blockers.pl connString nodeName dbName " if ($#ARGV != 2);

my ($connString, $node, $dbSID) = @ARGV;

my $threshold=2;

my %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );

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

my %countHash;
my $blocksFile = "$OpenNMSHome/etc/blockers_$dbSID.txt";
open BLOCKSFILE, "<$blocksFile";
while ( $_ = <BLOCKSFILE> ){
    chomp $_;
    my ($Ix,$count) = split(",",$_);
    $countHash{$Ix} = 0-$count;
}
close BLOCKSFILE;

my $dbh = DBI->connect("dbi:ODBC:DRIVER={ODBC Driver 17 for SQL Server};$connString");

die "Check4Blockers.pl can not connect to db ERR |" if ( ! $dbh );


my $arraySelect = $dbh->prepare("
sp_who2
") or die "Check4Blockers.pl $! ERR |";

print "about to execute\n";
$arraySelect->execute();
while (my ($SPID,$Status,$Login,$HostName,$BlkBy,$DBName,$Command,$CPUTime,$DiskIO,$LastBatch,$ProgramName,$SPID2,$RequestID) = $arraySelect->fetchrow_array()) {
   next if ($BlkBy eq '  .');
   next if ($Login eq 'NTSERVICE\SQLSERVERAGENT');
   next if ($Login eq 'abbmon');
   my $Ix = "$SPID$Login$BlkBy$DBName$Command";
   $countHash{$Ix} = abs($countHash{$Ix}) + 1;
   print "$SPID,$Login,$BlkBy,$DBName,$Command,$countHash{$Ix}\n";

   if ( $countHash{$Ix} > $threshold ) {
        my $errorMsg = sprintf( "Blocking session detected: DBName: %s SPID: %s Login: %s Command: %s Blocking SPID %s", $DBName, $SPID, $Login, $Command, $BlkBy);
        my $resourceID = $DBName.":".$Login.":".$SPID.":".$BlkBy;
        $resourceID =~ s/\s+//g;
     	system "send-event.pl uei.opennms.org/ABBCS/MSSQL/blocker-$errSev -n $nodeid -d \"SQLServer\" -p \"label Blocker\" -p \"resourceId $resourceID\" -p \"ds sqlBlocker\" -p \"description $errorMsg.\" -p \"SPID $SPID\"";

   }

   
}
$arraySelect->finish();

$dbh->disconnect();
open BLOCKSFILE, ">$blocksFile";
while (my ($k, $v) = each %countHash)
{
   if ( $v > 0 )
   {
      print BLOCKSFILE "$k,$v\n";
   }  
}

exit 0;


