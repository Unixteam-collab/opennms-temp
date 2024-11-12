#!/usr/bin/perl 
# Author : Gerald Talton 
#
# Program: onsdirproc.pl
#
# Purpose: to monitor the incoming directory and create remedy tickets from event files found
#
# Version: 3.2
#
# History: 15-Feb-2017 2.0 JDB  Updated for OpenNMS
#          30-Jun-2017 2.1 JDB  Updated code to drop events when a server is in a scheduled outage
#          06-Jul-2017 2.2 JDB  Updated  outage handler to correctly delete event files
#          06-Sep-2017 2.3 JDB  Seperated out the prelim event submission
#          10-Jun-2019 3.0 JDB  Re-written for OpsGenie support
#          30-Oct-2019 3.1 JDB	preserve newline in $message
#          15-Apr-2020 3.2 JDB	check URI to determine if fqdn names should be used for ticket submission
#                               this is to maintain continuity between Remedy Force Token ID and OpsGenie Entity name
#          14-Jul-2023 3.3 MPR  Commented-out $fqdnnode node outage check, no longer works after migration to
#                               Hitachi Energy network, causes genuine Events to be dropped and not logged to OpsGenie
#

use File::Copy;
#use DBI;
use POSIX qw(strftime);
use Fcntl qw(:flock);
use Log::Log4perl qw(:easy);
use Switch;
use String::Escape qw(unbackslash);



sub source {
    my $name = shift;

    open my $fh, "<", $name
        or die "could not open $name: $!";

    while (<$fh>) {
        chomp;
        my ($k, $v) = split /=/, $_, 2;
        $v =~ s/^(['"])(.*)\1/$2/; #' fix highlighter
        $v =~ s/\$([a-zA-Z]\w*)/$ENV{$1}/g;
        $v =~ s/`(.*?)`/`$1`/ge; #dangerous
        $ENV{$k} = $v;
    }
}



#
# Sub
#
# Taken from http://perl.about.com/od/email/a/perlemailsub.htm
#       Simple Email Function
#       ($to, $from, $subject, $message)
sub sendEmail
{
    my ($to, $from, $subject, $message) = @_;
    my $sendmail = '/usr/lib/sendmail';
    open(MAIL, "|$sendmail -oi -t");
    print MAIL "From: $from\n";
    print MAIL "To: $to\n";
    print MAIL "Subject: $subject\n\n";
    print MAIL "$message\n";
    close(MAIL);
} 


#############################
# Log4Perl Option           #
#############################
my $basedir = "/opt/rfinteg";
# Initialize Logger
my $log_conf = "${basedir}/etc/logger.conf";
Log::Log4perl::init($log_conf);
my $logger = Log::Log4perl->get_logger();

source "/opt/opennms/.ABBCS_Config_defaults/defaults";

my $USE_OPSGENIE = $ENV{"USE_OPSGENIE"};
my $USE_PROXY = $ENV{"USE_PROXY"};
my $PROXY = "";
if ( "$USE_PROXY" == "true" ) {
   $PROXY = $ENV{"proxy"};
   $ENV{"HTTP_PROXY"} = "$PROXY";
   $ENV{"HTTPS_PROXY"} = "$PROXY";
}

my $FQDN_TICKET = "false";
my $URI = $ENV{"URI"};
if ( "$URI" =~ "fqdn" ) {
   $FQDN_TICKET = "true";
}  

# locking file
sub BailOut {
    $logger->warn("$0 is already running. Exiting");
    $logger->warn("File '$lockfile' is locked");
    exit(1);
}

#############################
#  Other defined variable   #
#############################
my $incoming = "${basedir}/var/incoming";
my $current = "${basedir}/var/current";
my $errordir = "${basedir}/var/error";
my $lockfile = "${basedir}/var/locks/onsdirproc.lock";
#
# Warning when onsdirproc.pl start to log file
#
$logger->warn("onsdirproc.pl started");
open(my $fhpid, '>', $lockfile) or $logger->error("open '$lockfile': $!");
flock($fhpid, LOCK_EX|LOCK_NB) or BailOut();
#
# END Warning when osndirproc.pl start to log file
#

my $catmapFile="/opt/rfinteg/etc/category.map";
my $lcatmapFile="/opt/rfinteg/etc/local_category.map";
my %catmapHash;
open CATMAPFILE, "<$catmapFile";
while ( $_ = <CATMAPFILE> ){
   chomp $_;
   next if /^#/;
   my ($category,$apikey) = split(",",$_);
   $catmapHash{$category} = $apikey;
}
close CATMAPFILE;
open LCATMAPFILE, "<$lcatmapFile";
while ( $_ = <LCATMAPFILE> ){
   chomp $_;
   next if /^#/;
   my ($category,$apikey) = split(",",$_);
   $logger->info("category api key override for $category");
   $catmapHash{$category} = $apikey;
}
close LCATMAPFILE;
               
$logger->info("OpsGenie Submitter checking directory $incoming");

    opendir(INQUEUE, "$incoming");
    while ( my $file = readdir(INQUEUE)) {
        if ( $file eq '.' || $file eq '..' || $file eq 'nohup.out' ) {
            next;
        }

#        $logger->info("Processing file $file");
        
        open(EVIDFILE, "$incoming/$file");
        @lines = <EVIDFILE>;
        close(EVIDFILE);
        chomp @lines;
      
        $logger->info("Processing file $file lines in file $#lines");

        my ($onsnode,$severity,$messgid,$message,$mesgrp,$rfmesgkey,$mesgkey,$subid,$rg,$envtype) = @lines;

	if ( $envtype eq 'non-prod' ) {
           $logger->info("remapping severity.  Current: $severity");
           switch($severity) {
              case "critical"            { $severity =  "minor" }
              case "major"          { $severity = "warning" }
              case "minor"          { $severity = "warning" }
              case "cleared"          { $severity = "cleared" }
              case "normal"          { $severity = "normal" }
              else              { $severity = "warning" }
           }
           $logger->info("severity remapped to: $severity");
        }

	if ( $envtype eq 'sandpit' ) {
           $message = "TEST ALERT - PLEASE DELETE. $message";
           $logger->info("Sandpit detected - Severity: $severity");
           #$logger->info("remapping severity.  Current: $severity");
           #switch($severity) {
           #   case "critical"            { $severity =  "warning" }
           #   case "major"          { $severity = "warning" }
           #   case "minor"          { $severity = "warning" }
           #   case "cleared"          { $severity = "cleared" }
           #   case "normal"          { $severity = "normal" }
           #   else              { $severity = "warning" }
           #}
           #$logger->info("severity remapped to: $severity");
        }

        # Remove DBSID from onsnode so that outage check can check server level
        my ($fqdnnode,$dbid) =  split /_/, $onsnode;
        my $ticketNode = $onsnode;

        my $node_outage = `/etc/testsvr $fqdnnode`;

        # No longer works after migration to Hitachi Energy network, causes genuine Events to be dropped. 
        #if ( $node_outage == 0 ) {
        #    $logger->info("Node $fqdnnode is currently in scheduled outage. Droping event.");
        #    copy("$incoming/$file", "$errordir/$file");
        #    unlink("$incoming/$file");
        #    next;
        #}


        # pad out bad characters from $message
        $logger->info("Message before : $message");
        $message = unbackslash($message);
        $message =~ s/[\$'"#@~!&*();?`><\\]+//g;
        $logger->info("Message after : $message");

        if ( $FQDN_TICKET =~ /false/ ) {
           
           my @hostArr = split(/\./,$onsnode);
           $ticketNode = $hostArr[0];
        }

        $logger->info("Before NA check");
        $logger->info("SubscriptionID=$subid");
        $logger->info("ResourceGroup=$rg");

	if ( "$subid" eq "" ) {
           $subid = "NotAvailable";
        }
        if ( "$rg" eq "" ) {
           $rg = "NotAvailable";
        }
        $logger->info("after NA check");
        $logger->info("SubscriptionID=$subid");
        $logger->info("ResourceGroup=$rg");


        $logger->info("Mesgrp: $mesgrp");
        my $account;
	if ( $envtype eq 'sandpit' ) {
            $account=$catmapHash{'_SANDPIT'};
        } else {
            if ( exists $catmapHash{$mesgrp} ) {
                $account=$catmapHash{$mesgrp};
            } else {
                $account=$catmapHash{'_default'};
    	    $logger->info("hit default account");
            }
        }
	$logger->info("using $account");

        $mesgrp =~ s/ /+/g;

        if ( $USE_OPSGENIE =~ /true/ ) { 
           $logger->info("USE_OPSGENIE = true; submitting to OpsGenie");
           my $commandStr = "/opt/opennms/scripts/Utilities/Ticketing/createOpsGenieIncident.pl $account $severity $ticketNode \"$mesgrp\" \"$messgid\" \"$mesgkey\" \"$subid\" \"$rg\" \"$message\" ";
           $logger->info($commandStr);
           
           my $createResults = `$commandStr`;
           $logger->info("Raw result: $createResults");
           ($res,$too,$req) = split(/,/,$createResults);
           ($c1,$result)=split(/:/,$res);
           ($c1,$requestId)=split(/:/,$req);
           $result =~ s/\"//g;
           $result =~ s/\}//g;
           $requestId =~ s/\"//g;
           $requestId =~ s/\}//g;
           chomp $requestId;

          

           if ( $result =~ m/Request will be processed/ ) {
               $logger->info("Request created with ID $requestId and result: $result");
           } else {
              $logger->error("No RemedyForce ticket generated. Error: $createResults");
#                  my $mailMessage = "Command: \n\n" . 
#                                    "$commandStr\n" . 
#                                    "Error message: \n\n${RFIncidentId}\n";
#                  sendEmail( "johnd.blackburn\@au.abb.com", "remedy_errors_notify\@abb.com", "ONSrem Failure for $servername and event $eventType", $mailMessage);
                copy("$incoming/$file", "$errordir/$file");
               `echo $RFIncidentId >> $errordir/$file`;
           }
        } else {
           $logger->info("USE_OPSGENIE = false; not submitted to OpsGenie");
        }

        unlink("$incoming/$file");
    }
    closedir INQUEUE;

