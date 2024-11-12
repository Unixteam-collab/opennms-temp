#!/usr/bin/env perl

use DBD::Oracle;
use Log::Log4perl;
use DBIx::Log4perl;

use strict;


Log::Log4perl->init("/home/opennms/etc/log4perl.conf");


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

die "Wrong arguements: check_ellipsebatch_longrun_debug.pl dbSid nodeName tableName dbuserid dbpasswd" if ($#ARGV != 4);

my ($dbSID, $nodeName, $tableName, $user, $passwd ) = @ARGV;

my $uuidFile="$OpenNMSHome/etc/" . $nodeName . "_longrun.uuid";
my $thresholdFile="$OpenNMSHome/etc/" . $nodeName . ".threshold";
my $targetDeviceId=qx { /opt/opennms/scripts/getNodeID.sh $nodeName};
chomp $targetDeviceId;



my  %sevToLoggerStringHash = ( 1 => 'crit', 2 => 'err', 3 => 'warn' );

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


my $dbh = DBIx::Log4perl->connect("dbi:Oracle:$dbSID", $user, $passwd, {AutoCommit => 0, RaiseError => 1, });
if ( ! $dbh  ) {
    printf "check_ellipsebatch_logrun.pl ERR \| longrun_count=0;;;;\n";
    exit 1;
}
my $logger = $dbh->dbix_l4p_getattr('dbix_l4p_logger');
$logger->debug('Connected to database');

my $threshold=0;


my $overDueBatchSelect = <<END;
select -- List of values to display with alert
       prog_name, dstrct_code, Start_Date, Start_Time, Runtime_Minutes, Median_Elapsed, Std_Deviation, Count_Instances, (4*Std_Deviation+Median_Elapsed + 5) as THRESHOLD, UUID
from
(
   with history as -- subquery to get runtime history from msf085
    ( select  prog_name,
              dstrct_code,
              round(sum(elapsed_minutes),5) as Elapsed_Minutes,
              round(avg(elapsed_minutes),5) as Average_Elapsed,
              round(median(elapsed_minutes),5) as Median_Elapsed,
              round(stddev(elapsed_minutes),5) as Std_Deviation,
              count(*) as Count_Instances        
      from (        
            select  prog_name,
                    dstrct_code,
                    1440 * (to_date(stop_date||stop_time_hhmmss,'YYYYMMDDHH24MISS') - to_date(start_date||start_time_hhmmss,'YYYYMMDDHH24MISS')) as Elapsed_Minutes
            from    ellipse.msf085 History
           )
      group by prog_name, dstrct_code
    )
     -- find executing jobs and return the run time for this job and the matching history
     select Executing.prog_name, Executing.dstrct_code, Executing.start_date, Executing.start_time,
            round((1440 * ((cast(SYSTIMESTAMP at time zone NVL(trim(tz.district_time_zone),sessiontimezone) as date)) 
            - to_date(Executing.start_date || Executing.start_time, 'YYYYMMDDHH24MI') ) ),5) as RUNTIME_MINUTES, 
            History.Median_elapsed, History.Count_Instances, History.Std_Deviation,
            Executing.UUID
     from Ellipse.MSF080 Executing
     inner join History on (history.dstrct_code = Executing.dstrct_code and History.prog_name = Executing.prog_name)
     inner join Ellipse.msf000_dc0002 tz on (tz.dstrct_code = Executing.dstrct_code)
     where Executing.process_Status = 'E'
    )
    -- Logic of what gets reported.
    -- The median is the middle history value which should remove outliers.
    -- 4 standard deviations should cover 99.9% of all the history records
    -- Adding another 5 minutes should cover for variation (hiccups) in very short jobs.
    -- This might not cater for "camel hump " cases
    -- For example, a job usually runs for a very short time, but if it finmds transactions to post it runs for a long time to process them.
    -- Similarly for end of month jobs.
-- ** threshold evaluation handled in the perl code **where Runtime_Minutes > (4*Std_Deviation+Median_Elapsed + 5)
order by 1,2,3,4,5
END

my $arraySelect = $dbh->prepare($overDueBatchSelect) or die $!;
my $longRunCount = 0;

$logger->debug('About to call execute');
$arraySelect->execute();
$logger->debug('Execute call completed');

while ( my ($prog_name, $district_code, $start_date, $start_time, $runtime_minutes, $median_elapsed, $std_deviation, $priorCount, $threshold, $uuid) = $arraySelect->fetchrow_array() ) {
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
     	system "send-event.pl uei.opennms.org/ABBCS/Batch/failure-$errSev -n $targetDeviceId -d \"Batch failure\" -p \"label Batch\" -p \"resourceId $prog_name:$uuid\" -p \"ds batchFailure\" -p \"description $errorMsg.\nTo change threshold, add/update entry in `hostname`:$thresholdFile\n\nFormat:\nPROGNAME,THRESHOLD,PRIORITY\" -p \"uuid $uuid\"";

        system "echo $uuid >> $uuidFile";
        $longRunCount = $longRunCount + 1;
    }
}
$arraySelect->finish();


$dbh->disconnect();

printf "check_ellipsebatch_longrun.pl OK | longrun_count=$longRunCount;;;;\n";

exit 0;

