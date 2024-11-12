#!/bin/bash


/opt/opennms/scripts/Utilities/Ticketing/onsdirproc.pl >> /opt/rfinteg/var/onsdirproc.log 2>> /opt/rfinteg/var/onsdirproc.err
# OpsGenie Ticket submission no longer required
#/opt/opennms/scripts/submit_tickets.pl >> /opt/rfinteg/var/submit_tickets.out 2>&1

