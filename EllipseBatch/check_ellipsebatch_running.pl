#!/usr/bin/perl

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

die "Wrong arguements: check_ellipsebatch.pl dbSid nodeName tableName dbuserid dbpasswd ERR" if ($#ARGV != 4);

#elliidtsdb1_elldev, elliidtsdb1, ellipse.msf080, $OpenNMSHome/etc/elliidtsdb1_elldev_prioritymap.txt, zenoss, zenoss
#ellprddb1_ellprd, ellprddb1, ellipse.msf080, ellprddb1_ellprd_prioritymap.txt, zenoss, zenoss
my ($dbSID, $nodeName, $tableName, $user, $passwd) = @ARGV;

my $scheduleFile="$OpenNMSHome/etc/" . $nodeName . ".schedule";
my $targetDeviceId=qx { /opt/opennms/scripts/getNodeID.sh $nodeName};
chomp $targetDeviceId;

#Truncate current time to five minutes
my $five_min = 5 * 60;
my $t = time;
my $t5min = int($five_min * (int( ($t/$five_min) )));
my @t5minint = localtime($t5min);
my $time_stamp5min = sprintf "%02d:%02d", $t5minint[2], $t5minint[1];


my %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );
my $progSev;

open SCHEDULEFILE, "<$scheduleFile";
while ( $_ = <SCHEDULEFILE> ){
    chomp $_;
    my ($progName,$requestParams,$checktime,$severity) = split(",",$_);
    next if $checktime != $time_stamp5min;
    if ( $severity > 0 && $severity < 4 ) {
        $progSev = $sevToLoggerStringHash{$severity};
    }


    my $dbh = DBI->connect("dbi:Oracle:$dbSID", $user, $passwd, {AutoCommit => 0 });
    if ( ! $dbh  ) {
        printf "check_ellipsebatch.pl ERR \| fail_count=0;;;;\n";
        exit 1;
    }


    my $arraySelect = $dbh->prepare("select uuid,count(*) from $tableName where process_status = 'E' and prog_name = '$progName' and request_params like '%$requestParams%' group by uuid") or die $!;

    $arraySelect->execute();
    my ($uuid,$count) = $arraySelect->fetchrow_array();
    if ( $count == 0 ) {
       my $errSev = 'warn';  #maps to a p3
#       $prog_name =~ s/\s+$//;
       my $errSev = $progSev;
       system "echo send-event.pl uei.opennms.org/ABBCS/Batch/notrunning-$errSev -n $targetDeviceId -d \"Batch not started\" -p \"label Batch\" -p \"resourceId $progName:$requestParams:$uuid\" -p \"ds batchFailure\" -p \"description Ellipse Batch not started for program $progName:$requestParams with UUID: $uuid\" -p \"uuid $uuid\" ";
    } 
else {
print "Found $progName:$requestParams $count\n";
}

  $arraySelect->finish();


  $dbh->disconnect();
}
close SCHEDULEFILE;

#printf "check_ellipsebatch.pl OK | fail_count=$failcount;;;;\n";

exit 0;

