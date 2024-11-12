#!/usr/bin/env perl

use DBD::Pg;
use strict;

my $OpenNMSHome = "/home/opennms";

my $driver = "Pg";
my $database = "opennms";
my $dsn = "DBI:$driver:dbname = $database; host = 127.0.0.1;port=5432";
my $user= "opennms";
my $passwd = "opennms";



#die "Wrong arguements: check_ellipsebatch.pl dbSid targetDeviceId tableName programPrioritymap dbuserid dbpasswd uuidFile ERR" if ($#ARGV != 6);

#my ($dbSID, $targetDeviceId, $tableName, $progPriortyTable, $user, $passwd, $uuidFile) = @ARGV;

my $dbh = DBI->connect("$dsn", $user, $passwd, {RaiseError => 1 })
   or die $DBI::errstr;
#if ( ! $dbh  ) {
#    printf "check_ellipsebatch.pl ERR \| fail_count=0;;;;\n";
#    exit 1;
#}


my $arraySelect = $dbh->prepare("WITH snmp AS
   (select i.nodeid,s.servicename
    from ipinterface AS i
    LEFT OUTER JOIN ifservices AS ifs ON i.id=ifs.ipinterfaceid
    LEFT OUTER JOIN service AS s ON ifs.serviceid=s.serviceid
    WHERE s.servicename='SNMP')
SELECT n.nodelabel, snmp.servicename
FROM node AS n
LEFT OUTER JOIN snmp ON n.nodeid=snmp.nodeid
WHERE servicename ISNULL
GROUP BY n.nodeid,snmp.servicename
ORDER BY nodelabel;
") or die $!;

printf "Nodes without SNMP:\n";

$arraySelect->execute();
while ( my ($node) = $arraySelect->fetchrow_array() ) {
    printf "   %s\n", $node;
}
$arraySelect->finish();


$dbh->disconnect();

#printf "check_ellipsebatch.pl OK | fail_count=$failcount;;;;\n";

exit 0;
