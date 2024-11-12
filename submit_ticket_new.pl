#!/bin/perl

# 
#
# Program Name: submit_tickets.pl
#
# Purpose: to poll the "incoming" directory and submit tickets via http to one of the Remedy force
#          integration servers
#
# Version: 1.0
#
# History: 2017-09-05  1.0  JDB  Initial Revision
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

sub AckOpenNMS {
    my $id = shift;

}

my $PRIMARY = $ENV{"PRIMARY"};
my $SECONDARY = $ENV{"SECONDARY"};
my $URI = $ENV{"URI"};

#print "p=$PRIMARY s=$SECONDARY u=$URI\n";

#sub send_ticket {
#    my($dest, $

my $browser = LWP::UserAgent->new;

opendir my $INCOMING, $SOURCE or die "Cannot open incoming directory $!";

my @tickets = readdir $INCOMING;

closedir $INCOMING;

foreach $ticket (@tickets)
{

   if ($ticket =~ /^[.]/) { next; }

   print "\n Ticket file: $ticket \n";

   open ( TICKET_FILE, "< $SOURCE/$ticket") or die "Can't open $ticket for read: $!";

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

   close TICKET_FILE or die "Cannot close $ticket $!";
 
 
 
   my $url = "http://$PRIMARY/$URI";
 
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
   
   if ($response->content == '256') {
      print "Ticket sent but Remedy Force CI not set to accept tickets.  Check $PRIMARY RF Integration logs\n";
      ackOpenNMS $eventid;
      unlink("$SOURCE/$ticket");
   } else {
      if ($response->content  == '0') {
         print "Ticket sent via $PRIMARY\n";
         unlink("$SOURCE/$ticket");

      }
      else {
         my $url = "http://$SECONDARY/$URI";
 
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
   
         if ($response->content == '256') {
            print "Ticket sent but Remedy Force CI not set to accept tickets.  Check $PRIMARY RF Integration logs\n";
            ackOpenNMS $eventid;
            unlink("$SOURCE/$ticket");
         } else {
            if ($response->content  == '0') {
               print "Ticket sent via $SECONDARY\n";
               unlink("$SOURCE/$ticket");
            } else {
               # need code in here to track failures and raise an email ticket if excessive...
               print "Ticket not sent\n";
            }
         }
      }
   }
}

