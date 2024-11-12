#!/usr/bin/perl -w
#
# Copyright 2013 Andrew Grimberg <agrimberg@linuxfoundation.org>
#
# @License GPL-2.0 <http://spdx.org/licenses/GPL-2.0>

use strict;
use LWP::UserAgent;
use MIME::Base64;
use Getopt::Long;
use Pod::Usage;
use JSON::XS;

sub doAlertType($$)
{
    my ($requestURL, $json) = @_;
    my ($userAgent, $request, $response);

    my $apikey = $::options{'apikey'};

    
    print STDERR "\nUse Customer CA: " . $ENV{'USE_CUSTOMER_CA'} . "\n";
    print STDERR "\nCustomer CA path: " . $ENV{'CUSTOMER_CA_PATH'} . "\n";

    if ($ENV{'USE_CUSTOMER_CA'} eq "true") {
       $userAgent = LWP::UserAgent->new(ssl_opts => {
          SSL_ca_file => "$ENV{'CUSTOMER_CA_PATH'}" });
    } else {
       $userAgent = LWP::UserAgent->new;
    }
    $userAgent->agent("OpsGenieScript/1.0");
    $userAgent->timeout(10);
    $userAgent->env_proxy();
    print STDERR "\nProxy: " . $ENV{'HTTPS_PROXY'} . "\n";

    $request = HTTP::Request->new(POST => $requestURL);

    $request->header('Authorization' => 'Basic ' . encode_base64($apikey));
    $request->header('Content-Type'  => 'application/json');

    $request->content($json);

    $response = $userAgent->request($request);

    if ($response->is_success) {
        print STDERR "\nNotification successfully posted.\nResponse code: " . $response->is_success . "\n" . $response->content . "\n";
    } else {
        print STDERR "\nNotification not posted: " . $response->content . "\n";
    }
    print $response->content ."\n";
}

# createAlert
# requires %ogArgs
#
# Connects to OpsGenie and creates the alert
sub createAlert(%)
{
    my %ogArgs = @_;
    my $json = encode_json \%ogArgs;

    my $requestURL = 'https://api.opsgenie.com/v2/alerts';
    doAlertType($requestURL, $json);
}

# closeAlert
# requires %ogArgs
#
# Connects to OpsGenie and closes the alert
sub closeAlert(%)
{
    my %ogArgs = @_;
    my $json = encode_json \%ogArgs;

    my $requestURL = 'https://api.opsgenie.com/v2/alerts/' . $ogArgs{'alias'} . '/close?identifierType=alias';
    doAlertType($requestURL, $json);
}

# Grab our options
our %options = ();
GetOptions(\%options, 'apikey=s', 'apikeyfile=s', 'application=s',
            'event=s', 'notification=s', 'priority=i',
            'recipients=s', 'tags=s',
            'servername=s', 'ONSeventtype=s', 'messagekey=s', 'eventid=s', 'severity=s', 'subid=s', 'resourcegroup=s', 'noautoclose', 'help|?') or pod2usage(2);

$options{'application'} ||= 'OpsGenieScript';
$options{'priority'} ||= 0;

pod2usage(-verbose => 2) if (exists($options{'help'}));
pod2usage(-message => "$0: Event type is required") if (!exists($options{'event'}) || (lc($options{'event'}) ne 'host' && lc($options{'event'}) ne 'service'));
$options{'event'} = lc($options{'event'});
pod2usage(-message => "$0: Notification text is required") if (!exists($options{'notification'}));
pod2usage(-message => "$0: ServerName is required") if (!exists($options{'servername'}));
pod2usage(-message => "$0: OpenNMS Event Type is required") if (!exists($options{'ONSeventtype'}));
pod2usage(-message => "$0: Messagekey is required") if (!exists($options{'messagekey'}));
pod2usage(-message => "$0: eventid is required") if (!exists($options{'eventid'}));
pod2usage(-message => "$0: subid is required") if (!exists($options{'subid'}));
pod2usage(-message => "$0: resourcegroup is required") if (!exists($options{'resourcegroup'}));
pod2usage(-message => "$0: Priority must be in the range [-2, 2]") if ($options{'priority'} < -2 || $options{'priority'} > 2);
pod2usage(-message => "$0: Recipient list is required") if (!exists($options{'recipients'}));

# Get the API key from STDIN if one isn't provided via a file or from the command line
if (!exists($options{'apikey'}) && !exists($options{'apikeyfile'})) {
    print "API Key: ";

    $options{'apikey'} = <STDIN>;
} elsif (exists($options{'apikeyfile'})) {
    open(APIKEYFILE, $options{'apikeyfile'}) or die($!);
    $options{'apikey'} = <APIKEYFILE>;
    close(APIKEYFILE);
}

# chomp the apikey in case it came in via STDIN or file
chomp $options{'apikey'};

# array of tags
my @tags = ("nodename=" . $options{'servername'});

if (exists($options{'tags'})) {
    push @tags, split(',', $options{'tags'});
}

# array of recipients
my @recipients;

for my $responder (split(',', $options{'recipients'})) {
    push @recipients, {
        "name"   => $responder,
        "type" => "team"
    }
}

# Setup our args block
my %ogArgs = (
        'entity' => $options{'servername'},
        'responders' => \@recipients,
        'alias' => $options{'messagekey'},
        'source' => $options{'application'},
        'message' => "[OpenNMS] $options{'notification'}",
        'note' => "$options{'notification'}",
        'tags' => \@tags
    );

# Add additional information if this is a host event or service
# also, do the determination to open or close the event and
# execute
#if ($options{'event'} eq 'host') {
#    if (($ENV{'NAGIOS_HOSTSTATE'} eq 'DOWN' || $ENV{'NAGIOS_HOSTSTATE'} eq 'UNREACHABLE')
#    		&& $ENV{'NAGIOS_NOTIFICATIONTYPE'} eq 'PROBLEM') {
#        $ogArgs{'details'} = {'host' => $ENV{'NAGIOS_HOSTNAME'}};
#        $ogArgs{'description'} = "***** Nagios *****
#
#Notification Type: $ENV{'NAGIOS_NOTIFICATIONTYPE'}
#Host: $ENV{'NAGIOS_HOSTNAME'}
#State: $ENV{'NAGIOS_HOSTSTATE'}
#Additional Info: $ENV{'NAGIOS_HOSTOUTPUT'}
#Date/Time: $ENV{'NAGIOS_LONGDATETIME'}
#";
#
#        createAlert(%ogArgs);
#    } elsif (!exists($options{'noautoclose'}) && $ENV{'NAGIOS_HOSTSTATE'} eq 'UP' && $ENV{'NAGIOS_NOTIFICATIONTYPE'} eq 'RECOVERY') {
#        closeAlert(%ogArgs);
#    }
#} else {

 #   $ogArgs{'alias'} = "$ogArgs{'alias'}_$ENV{'cwNAGIOS_SERVICEDESC'}";
 #   if (($ENV{'NAGIOS_SERVICESTATE'} eq 'CRITICAL' || $ENV{'NAGIOS_SERVICESTATE'} eq 'WARNING') &&
 #       $ENV{'NAGIOS_NOTIFICATIONTYPE'} eq 'PROBLEM') {
        $ogArgs{'details'} = {
                                'Category' => $options{'ONSeventtype'},
                                'MessageKey' => $options{'messagekey'},
                                'EventID' => $options{'eventid'},
                                'Severity' => $options{'severity'},
                                'SubscriptionId' => $options{'subid'},
                                'ResourceGroup' => $options{'resourcegroup'},
                            };
        $ogArgs{'description'} = "***** OpenNMS *****

Message: $options{'notification'}
";
        createAlert(%ogArgs);
#    } elsif (!exists($options{'noautoclose'}) &&
#        $ENV{'NAGIOS_SERVICESTATE'} eq 'OK' && $ENV{'NAGIOS_NOTIFICATIONTYPE'} eq 'RECOVERY') {
#        closeAlert(%ogArgs);
#    }
#}

__END__

=head1 NAME

opsgenie - Create and close events in OpsGenie for Nagios


=head1 SYNOPSIS

opsgenie.pl [options] event_information

 Options:
   -help                Display all help information.
   -apikey=...          Your OpsGenie API key.
   -apikeyfile=...      A file contianing your OpsGenie API key.
   -recipients=...      A comma separated list of OpsGenie recipients
                        This must be quoted if you have spaces in the list

 Event information:
   -application=...     The name of the application.
   -event=...           The name of the event. Must be host or service.
   -notification=...    The text of the notification.
   -priority=...        The priority of the notification.
                        An integer in the range [-2, 2].
                        This will be passed a tag of priority=N
                        to OpsGenie.
   -tags=...            A comma separated string of additional
                        tags to pass to OpsGenie.
   -noautoclose         Disable the autoclose of events

 ONS integration information:
   -servername=...	The OpenNMS Node name
   -ONSeventtype=...	OpenNMS Event type
   -messagekey=...      Message key for event corelation
   -eventid=...		Event ID to track back to OpenNMS source Event
   -severity=...	OpenNMS Severity

=head1 DESCRIPTION

B<This program> creates and closes issues against OpsGenie, which will
then forward these alerts to the person, or parties defined by the
receiving policy. It is intended that this be executed by Nagios for
alerting as it relies upon several environment variables that Nagios sets.

=head1 OPTIONS

=over 8

=item B<-apikey>

Your OpsGenie API key. It is not recommended that you use this, use the
apikeyfile option.

=item B<-apikeyfile>

A file containing one line, which has your OpsGenie API key on it. This
is the recommended method of passing in your key.

=item B<-recipients>

A comma separated list of OpsGenie recipients. This must be quoted if
you have spaces in the list. Recipients may be email addresses,
notification groups, escalations or schedules. If you can route a
message to it in OpsGenie it can be used here.

=item B<-application>

The name of the Application part of the notification. If none is
provided, OpsGenieScript is used.

=item B<-event>

The type of event that this is. It must be either host or service (case
does not matter)

=item B<-notification>

The text of the notification, which has more details for a particular
event. This is generally the description of the action which occurs,
such as "The disk /dev/abc was successfully partitions."

=item B<-priority>

The priority level of the notification. An integer value ranging [-2, 2]
with meanings of Very Low, Moderate, Normal, High, Emergency. This is
passed to OpsGenie as a tag in the form of priority=N

=item B<-tags>

A comma separated list of tags to pass to OpsGenie. These tags will be
sent along with the priority.

=item B<-noautoclose>

By default events will be automatically closed if the script detects
that this is a Nagios RESOLUTION. Setting this flag will disable this
feature.

=back

=head1 HELP

For assistance with this script in particular, visit the GitHub site at
<https://github.com/tykeal/nagios_opsgenie/issues>.

For assistance with OpsGenie, visit the OpsGenie site at
<https://www.opsgenie.com>.

=head1 COPYRIGHT

Copyright 2013 Andrew Grimberg

Distributed under the GPLv2

=cut
