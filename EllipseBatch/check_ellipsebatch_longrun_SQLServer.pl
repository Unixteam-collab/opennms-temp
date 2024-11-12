#!/usr/bin/env perl

use DBI;
use strict;


my $OpenNMSHome = "/home/opennms";

die "Wrong arguements: check_ellipsebatch_longrun_SQLServer.pl connString nodeName tableName " if ($#ARGV != 2);

my ($connString, $nodeName, $tableName) = @ARGV;

my $uuidFile="$OpenNMSHome/etc/" . $nodeName . "_longrun.uuid";
my $thresholdFile="$OpenNMSHome/etc/" . $nodeName . ".threshold";
my $targetDeviceId=qx { /opt/opennms/scripts/getNodeID.sh $nodeName};
chomp $targetDeviceId;

my %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );

my %progSevHash;

my %uuidHash;
open UUIDFILE, "<$uuidFile";
while ( $_ = <UUIDFILE> ){
    chomp $_;
    $uuidHash{$_} = 1;
}
close UUIDFILE;

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
    printf "check_ellipsebatch_logrun.pl ERR \| longrun_count=0;;;;\n";
    exit 1;
}

my $overDueBatchSelect = <<END;
select running.prog_name, running.uuid, running.DSTRCT_CODE,
      DATEDIFF(minute,substring(running.START_DATE,1,4)+'-'+substring(running.START_DATE,5,2)+'-'+substring(running.START_DATE,7,2)+' '+substring(running.START_TIME,1,2)+':'+substring(running.START_TIME,3,2)+':00',GETDATE()) RUNTIME_MINUTES, thresholds.PRIORCOUNT, THRESHOLD
  from ellipse.msf080 running
  left outer join
     (select prog_name, dstrct_code, count(*) PRIORCOUNT,
       avg(DATEDIFF(minute,
           substring(start_date,1,4)+'-'+substring(start_date,5,2)+'-'+substring(start_date,7,2)+' '+substring(start_time_hhmmss,1,2)+':'+substring(start_time_hhmmss,3,2)+':'+substring(start_time_hhmmss,5,2),
           substring(stop_date,1,4)+'-'+substring(stop_date,5,2)+'-'+substring(stop_date,7,2)+' '+substring(stop_time_hhmmss,1,2)+':'+substring(stop_time_hhmmss,3,2)+':'+substring(stop_time_hhmmss,5,2))
) + ( 4 * stdev (DATEDIFF(minute,
substring(start_date,1,4)+'-'+substring(start_date,5,2)+'-'+substring(start_date,7,2)+' '+substring(start_time_hhmmss,1,2)+':'+substring(start_time_hhmmss,3,2)+':'+substring(start_time_hhmmss,5,2),
substring(stop_date,1,4)+'-'+substring(stop_date,5,2)+'-'+substring(stop_date,7,2)+' '+substring(stop_time_hhmmss,1,2)+':'+substring(stop_time_hhmmss,3,2)+':'+substring(stop_time_hhmmss,5,2))
) ) THRESHOLD
       from ellipse.msf085
       group by prog_name, dstrct_code
      ) thresholds
  on ( running.prog_name = thresholds.prog_name AND running.DSTRCT_CODE = thresholds.DSTRCT_CODE )
  where running.process_status = 'E' and REQUEST_REC_NO = '01'
END

my $arraySelect = $dbh->prepare($overDueBatchSelect) or die $!;
my $longRunCount = 0;

$arraySelect->execute();
while ( my ($prog_name, $uuid, $district_code, $runtime_minutes, $priorCount, $threshold) = $arraySelect->fetchrow_array() ) {
    #printf "%s %s %s %d %d %d\n", $prog_name, $uuid, $district_code, $runtime_minutes, $priorCount, $threshold;
    $prog_name =~ s/\s+$//;
    if ( exists $uuidHash{$uuid} ) {
       print " got $prog_name with runtime $runtime_minutes.  UUID $uuid already alerted.  Skipping\n";
       next;
    }

    if ( exists $thresholdHash{$prog_name} ) {
       print "got $prog_name threshold $threshold replacing with $thresholdHash{$prog_name}\n";
       $threshold = $thresholdHash{$prog_name};
    } else {
       print "got $prog_name UUID $uuid threshold $threshold but did not find an override threshold\n";
       if ( $priorCount < 3 ) {
          print "prior execution count <3. Skipping\n";
          next;
       }
    }
       
    if ( $threshold < 0 ) {
       print "got $prog_name with manually configured negative Treshold of $threshold.  Skipping\n";
       next;
    }
    if ( $threshold == 0 ) {   # if we have absolutely no history then set a 1 hr threshold
        print "got $prog_name UUID $uuid with threshold = $threshold.  Defaulting threshold to 60\n";
        $threshold = 60;
    }
    print  "testing $prog_name with threshold $threshold against runtime of $runtime_minutes\n";
    if ( $runtime_minutes+0 > $threshold ) {
        my $errSev = 'warn';  #maps to a p4
        if ( exists $progSevHash{$prog_name} ) {
            $errSev = $progSevHash{$prog_name};
        }
        my $errorMsg = sprintf( "Ellipse Batch Running too long - %s running for %.2f minutes with threshold of %.2f minutes with UUID %s from %s", $prog_name, $runtime_minutes, $threshold, $uuid, $nodeName);
        print "$errorMsg\n";
     	system "send-event.pl uei.opennms.org/ABBCS/Batch/failure-$errSev -n $targetDeviceId -d \"Batch failure\" -p \"label Batch\" -p \"resourceId $prog_name:$uuid\" -p \"ds batchFailure\" -p \"description $errorMsg.  To change threshold, add/update entry in `hostname`:$thresholdFile  Format PROGNAME,THRESHOLD,PRIORITY\" -p \"uuid $uuid\"";
        system "echo $uuid >> $uuidFile";
        $longRunCount = $longRunCount + 1;
    }
}
$arraySelect->finish();


$dbh->disconnect();

printf "check_ellipsebatch_longrun.pl OK | longrun_count=$longRunCount;;;;\n";

exit 0;

