#!/usr/bin/perl

#use lib '/`opt/rfinteg/onsrem/bin';

#chdir( "/opt/rfinteg/onsrem/bin" );


use Log::Log4perl;

#use Data::Dumper;

$| = 1;

my $HOSTNAME = `/bin/hostname -s`;

my $account = shift @ARGV;
my $severity = shift @ARGV;
my $servername = shift @ARGV;
my $eventType = shift @ARGV;
my $eventID = shift @ARGV;
my $messageKey = shift @ARGV;
my $subscriptionID = shift @ARGV;
my $resourceGroup = shift @ARGV;
my $eventMessage = join(' ',@ARGV);
$eventMessage =~ s/[']//g;
#$eventMessage =~ s/\s+/ /g;
$eventMessage = "$eventMessage \n\n Node name: $servername\n Event ID: $eventID\n Message Key: $messageKey\n Submitted from $HOSTNAME";

     
   #severity will only ever be 'critical', 'major', 'minor' or 'warning'
#   my %severityMap = ( 'CRIT' => 'critical', 'MAJR' => 'major', 
#   		    'MINR' => 'minor', 'WARN' => 'warning' );
   
#   # first do a category parent lookup 
#   my $zenossCategoryParentId = $curRFobj->getCategoryIdWhereName( "OpenNMS" );
#   die "Initial Category parent query failed." unless ( defined( $zenossCategoryParentId ));
   
#   # next using that parent key do a category lookup
#	# printf "DEBUG: %s\n",$eventType;
   $eventType =~ s/\+/ /g;
#	# printf "DEBUG: %s\n",$eventType;
#   my $RFeventType = $eventType;
#   my $categoryId = $curRFobj->getCategoryIdWithParentWhereName( $zenossCategoryParentId, $RFeventType);
#   die "Undefined category query failed." unless ( length( $categoryId ));
   
   #next lookup device/server in CMDB
#   my @serverNameArr = split( /\./, $servername);
#   $servername = $serverNameArr[0];
   $servername =~ tr/a-z/A-Z/;
#   my @resultArr = $curRFobj->getBaseElementIdFromToken($servername);
#   my ($baseElemId, $baseElemClass, $baseElemInstanceId, $baseElemBizImpact, $ciStatus, $SLA_Ref__c, $appAlertCatStr, $appSupportQueue, $hardwareSupportQueue);
#   my ($targetQueue, $newOwnerId);
#   if ( $#resultArr == 5 ) {
#       ($baseElemId, $baseElemClass, $baseElemInstanceId, $baseElemBizImpact, $ciStatus, $SLA_Ref__c ) = @resultArr;
#   } elsif ( $#resultArr == 8 ) {
#       ($baseElemId, $baseElemClass, $baseElemInstanceId, $baseElemBizImpact, $ciStatus, $SLA_Ref__c, $appAlertCatStr, $appSupportQueue, $hardwareSupportQueue) = @resultArr;
#       if ( defined( $appAlertCatStr ) && $appAlertCatStr =~ /$RFeventType/i ) {
#   	$targetQueue = $appSupportQueue if (defined($appSupportQueue));
#       } else {
#   	$targetQueue = $hardwareSupportQueue if (defined($hardwareSupportQueue));
#       }
#       $newOwnerId = $curRFobj->getQueueFKforName( $targetQueue ) if (defined($targetQueue));
#   } else {
#       die "CI hostname lookup failed\n";
#   }
   
   # if the CI status is not "In Service" then abort this incident create
#   if ( $ciStatus ne "In Service" ) {
#       printf "Server $servername not in service incident open aborted\n";
#       exit(0);
#   }
   
#   
   # if the CI record has App and Hardware support groups defined then use it
#   if ( defined( $newOwnerId ) ) {
#       $incidentHash{"OwnerId"} = $newOwnerId;
#   }
   

    my $commandStr = "/opt/opennms/scripts/Utilities/Ticketing/opsgenie.pl -apikeyfile=/opt/rfinteg/etc/api-keys/$account -recipients=es-cloud-monitoring -application=OpenNMS -servername=$servername -ONSeventtype=\"$eventType\" -messagekey=$messageKey -eventid=$eventID -severity=$severity -event=host -notification=\'$eventMessage\' -subid=\"$subscriptionID\" -resourcegroup=\"$resourceGroup\" -tags=\"messageKey=$messageKey\" ";
    printf STDERR "Command: %s\n". $commandStr;
    my $output = `$commandStr`;
    printf "%s". $output;
# 
#   my $incidentId = 0;
#   if ( ref($incidentCreateResult) eq "HASH" &&
#        $incidentCreateResult->{'success'} eq true ) {
#       $incidentId = $incidentCreateResult->{'id'};
#   } else {
#       die "incident create error : $incidentCreateResult->{'errors'}[0]\n";
#   }
   
#   my %testEventCILinkHash = (
#     "BMCServiceDesk__FKIncident__c" => $incidentId,
#     "BMCServiceDesk__FKConfiguration_Item__c" => $baseElemId,
#   );
   
#   my $ciLinkCreateResult = $curRFobj->makeACJSONPostCall( "/sobjects/BMCServiceDesk__Incident_CI_Link__c/", \%testEventCILinkHash );
   
#   my $incidentGetCall = $curRFobj->makeACJSONGetCall( "/sobjects/BMCServiceDesk__Incident__c/${incidentId}" );
   
#   printf STDERR "Id %s Name %s\n", $incidentId, $incidentGetCall->{'Name'};
   
   # Annotate OV source event with Remedy Force Call details
#   my @cmd = ('/opt/OV/bin/OpC/opcannoadd');
#   push @cmd, "$eventID";
#   push @cmd, "Remedy Force call raised: Id $incidentId Name $incidentGetCall->{'Name'}";
#   system (@cmd);
   
#}

my $x = 1;

exit 0;

