#!/usr/bin/env perl

use DBI;
use strict;

my $OpenNMSHome = "/home/opennms";


# for PaaS, Connection string format:
# 'Server=tcp:MYDATABASE.database.windows.net,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'
# for IaaS, Connection String Format:
# 'Server=tcp:10.123.25.22,1433;Database=MYDATABASE;Uid=USER;Pwd=PASSWORD;Connection Timeout=30;'


die "Wrong arguements: check_ellipsebatch.pl 'ConnectString' targetDeviceId tableName programPrioritymap uuidFile ERR" if ($#ARGV != 4);

my ($connString, $targetDeviceId, $tableName, $progPriortyTable, $uuidFile) = @ARGV;



my %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );

my %progSevHash;
open PRIORITYTABLE, "<$OpenNMSHome/etc/$progPriortyTable";
while ( $_ = <PRIORITYTABLE> ){
    chomp $_;
    my ($progName,$severity) = split(",",$_);
    if ( $severity > 0 && $severity < 4 ) {
	$progSevHash{$progName} = $sevToLoggerStringHash{$severity};
    }
}
close PRIORITYTABLE;

my %uuidHash;
open UUIDFILE, "<$OpenNMSHome/etc/$uuidFile";
while ( $_ = <UUIDFILE> ){
    chomp $_;
    $uuidHash{$_} = 1;
}
close UUIDFILE;

my $dbh = DBI->connect("dbi:ODBC:DRIVER={ODBC Driver 17 for SQL Server};$connString");
if ( ! $dbh  ) {
    printf "check_ellipsebatch.pl ERR \| fail_count=0;;;;\n";
    exit 1;
}

my $failcount = 0;

my $arraySelect = $dbh->prepare("select prog_name, process_status,uuid,start_date from $tableName where process_status = 'F'") or die $!;

$arraySelect->execute();
while ( my ($prog_name, $process_status, $uuid, $start_date) = $arraySelect->fetchrow_array() ) {
    #printf "%s %s %s %s\n", $prog_name, $process_status, $uuid, $start_date;
    next if exists $uuidHash{$uuid};
    my $errSev = 'warn';  #maps to a p3
    $prog_name =~ s/\s+$//;
    if ( exists $progSevHash{$prog_name} ) {
	$errSev = $progSevHash{$prog_name};
    }
    system "send-event.pl uei.opennms.org/ABBCS/Batch/failure-$errSev -n $targetDeviceId -d \"Batch failure\" -p \"label Batch\" -p \"resourceId $prog_name:$uuid\" -p \"ds batchFailure\" -p \"description Ellipse Batch failure for program $prog_name with UUID: $uuid\" -p \"uuid $uuid\" ";

    system "echo $uuid >> $OpenNMSHome/etc/$uuidFile";
    $failcount = $failcount + 1;
}
$arraySelect->finish();


$dbh->disconnect();

printf "check_ellipsebatch.pl OK | fail_count=$failcount;;;;\n";

exit 0;
