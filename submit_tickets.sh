#!/bin/bash

###################
#
#  filename: submit_tickets.sh
#
#  purpose: to fetch generated events from opennms incoming directory
#           and submit to RF integration servers
#
#  Version: 1.0
#
#  History: JDB  10-7-2017 1.0  Initial Revision
#
###################

VAR=/opt/rfinteg/var
SOURCE=$VAR/incoming


if [ ! -d ${VAR}/locks ]
then
   mkdir -p ${VAR}/locks
fi

# look for tickets to submit
for TICKET in $SOURCE/*
do

    
    

done

