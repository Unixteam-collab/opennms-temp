#!/usr/bin/env perl

use DBD::Oracle;
use strict;

#my $oraHome = "/oracle/product/12.1.0/client_1";
my $oraHome = `dirname \$\(find /oracle -name oraInst.loc 2> /dev/null\)`;
chomp $oraHome;
$oraHome =~ s/\s+$//;

my $oraBase = "/oracle";
my $OpenNMSHome = "/home/opennms";

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

die "Wrong arguements: check_ellipsebatch.pl dbSid targetDeviceId tableName programPrioritymap dbuserid dbpasswd uuidFile ERR" if ($#ARGV != 6);

#elliidtsdb1_elldev, elliidtsdb1, ellipse.msf080, $OpenNMSHome/etc/elliidtsdb1_elldev_prioritymap.txt, zenoss, zenoss
#ellprddb1_ellprd, ellprddb1, ellipse.msf080, ellprddb1_ellprd_prioritymap.txt, zenoss, zenoss
my ($dbSID, $targetDeviceId, $tableName, $progPriortyTable, $user, $passwd, $uuidFile) = @ARGV;

my %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );
#my %sevToLoggerStringHash = ( 1 => '', 2 => '2', 3 => '3' );

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

my $dbh = DBI->connect("dbi:Oracle:$dbSID", $user, $passwd, {AutoCommit => 0 });
if ( ! $dbh  ) {
    printf "check_ellipsebatch.pl ERR \| fail_count=0;;;;\n";
    exit 1;
}

my $failcount = 0;

my $arraySelect = $dbh->prepare("select prog_name, process_status,uuid,start_date from $tableName where process_status = 'F'") or die $!;

$arraySelect->execute();
while ( my ($prog_name, $process_status, $uuid, $start_date) = $arraySelect->fetchrow_array() ) {
    #printf "%s %s %s %s\n", $prog_name, $process_status, $uuid, $start_date;
    # zensendevent --device MYDEVICE --component DEVICECOMPONENT --eventclasskey MYEVENTCLASSKET --severity Info|Debug|Clear|Error|Warning|Critical --class MYEVENTCLASS --server MYZENOSSSERVER --auth admin:zenoss (default)
    next if exists $uuidHash{$uuid};
    my $errSev = 'warn';  #maps to a p3
    $prog_name =~ s/\s+$//;
    if ( exists $progSevHash{$prog_name} ) {
	$errSev = $progSevHash{$prog_name};
    }
#    system "logger -p local0.${errSev} \"Ellipse Batch failure for program $prog_name with UUID: $uuid from target device: $targetDeviceId\"";
#     print "send-event.pl uei.opennms.org/ABBCS/Batch/failure -s Batch -n $targetDeviceId -d \"Batch failure\" -x $errSev -p \"label $prog_name\" -p \"ds batchFailure\" -p \"description Ellipse Batch failure for program $prog_name with UUID: $uuid\" -p \"uuid $uuid\" ";
     system "send-event.pl uei.opennms.org/ABBCS/Batch/failure-$errSev -n $targetDeviceId -d \"Batch failure\" -p \"label Batch\" -p \"resourceId $prog_name:$uuid\" -p \"ds batchFailure\" -p \"description Ellipse Batch failure for program $prog_name with UUID: $uuid\" -p \"uuid $uuid\" ";

    system "echo $uuid >> $OpenNMSHome/etc/$uuidFile";
    $failcount = $failcount + 1;
}
$arraySelect->finish();


$dbh->disconnect();

printf "check_ellipsebatch.pl OK | fail_count=$failcount;;;;\n";

exit 0;
