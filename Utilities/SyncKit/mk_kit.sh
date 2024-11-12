#!/bin/bash

BASE=/opt/opennms/scripts/Utilities

if [ ! -d $BASE/SyncKit ]
then
   echo Error: SyncKit source dir does not exist on this server.
   echo This script is only useful for creating tarball on opennms server.
   exit 1
fi


cd $BASE
tar cfz SyncKit_$(date +%Y%m%d).tgz SyncKit

