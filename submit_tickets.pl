#!/bin/perl

# 
#
# Program Name: submit_tickets.pl
#
# Purpose: to poll the "incoming" directory and submit tickets via http to one of the Remedy force
#          integration servers
#
# Version: 1.2
#
# History: 2017-09-05  1.0  JDB  Initial Revision
#          2018-10-25  1.1  JDB  Updated to correctly handle non-responsive RF integration server
#          2019-06-11  1.2  JDB  Updated to allow environment variable to disable RF ticket submission,
#                                and to pass off ticket deletion to the OpsGenie ticket submitter
#


use LWP::UserAgent;

my $SOURCE = "/opt/rfinteg/var/incoming";

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


source "/opt/opennms/.ABBCS_Config_defaults/defaults";

my $PRIMARY = $ENV{"PRIMARY"};
my $SECONDARY = $ENV{"SECONDARY"};
my $URI = $ENV{"URI"};

print "passed URI = $URI \n";
if ($URI =~ m|^/|) {
  print "Got a slash\n";
} else {
  print "Got no slash\n";
  $URI = "/$URI";
}
print "processed URI = $URI\n";


my $USE_RF = $ENV{"USE_RF"};
my $DATESTRING = localtime();

print "$DATESTRING\n";

#print "p=$PRIMARY s=$SECONDARY u=$URI\n";

#sub send_ticket {
#    my($dest, $

my $browser = LWP::UserAgent->new;

opendir my $INCOMING, $SOURCE or die " Cannot open incoming directory $!";

my @tickets = readdir $INCOMING;

closedir $INCOMING;

foreach $ticket (@tickets)
{

   if ($ticket =~ /^[.]/) { next; }

   print "\n Ticket file: $ticket \n";

   open ( TICKET_FILE, "< $SOURCE/$ticket") or die " Can't open $ticket for read: $!";

   my $node = <TICKET_FILE>;
   chomp $node;
   my $severity = <TICKET_FILE>;
   chomp $severity;
   my $eventid = <TICKET_FILE>;
   chomp $eventid;
   my $message = <TICKET_FILE>;
   chomp $message;
   my $category = <TICKET_FILE>;
   chomp $category;
   my $msgkey = <TICKET_FILE>;
   chomp $msgkey;

   close TICKET_FILE or die " Cannot close $ticket $!";
 
   if ($severity =~ /cleared/) { next;} 
   if ($severity =~ /Cleared/) { next;} 
 
   my $url = "http://$PRIMARY$URI";
 
   my $response = $browser->post($url,
     [    'fqdnnode' => "$node",
          'severity' => "$severity",
          'messgid' => "$eventid",
          'message' => "$message",
          'mesgrp' => "$category",
          'mesgkey' => "$msgkey",
          'end' => "End",
     ]
   );
   
   if ($response->is_success() && $response->content == '0') {
      print " Ticket sent via Primary: $PRIMARY\n";
      # removed unlink as this will now be left for the opsgenie script to handle
      #unlink("$SOURCE/$ticket");

   } else {

      print " error:\n";
      print $response->message();
      print "\n Failed to send via Primary: $PRIMARY.  Attempting Secondary: $SECONDARY\n";

      my $url = "http://$SECONDARY$URI";
 
      my $response = $browser->post($url,
        [    'fqdnnode' => "$node",
             'severity' => "$severity",
             'messgid' => "$eventid",
             'message' => "$message",
             'mesgrp' => "$category",
             'mesgkey' => "$msgkey",
             'end' => "End",
        ]
      );
   
      if ($response->is_success() && $response->content == '0') {
         print "Ticket sent via Secondary: $SECONDARY\n";
         # removed unlink as this will now be left for the opsgenie script to handle
         #unlink("$SOURCE/$ticket");
      } else {
         # need code in here to track failures and raise an email ticket if excessive...
         print " Failed to send via Secondary $SECONDARY\nError:\n";
         print $response->message();
         print "\n Ticket not sent\n";
      }
   }
} # end foreach

