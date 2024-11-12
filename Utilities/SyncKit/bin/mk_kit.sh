#!/bin/bash

OPENNMS_HOME=/opt/opennms
BASE=$OPENNMS_HOME/scripts/Utilities
TARFILE=SyncKit_$(date +%Y%m%d).tgz 
LINK=SyncKit-current.tgz

if [ ! -d $BASE/SyncKit ]
then
   echo Error: SyncKit source dir does not exist on this server.
   echo This script is only useful for creating tarball on opennms server.
   exit 1
fi


cd $BASE
cp $OPENNMS_HOME/scripts/outage.sh $BASE/SyncKit/bin
tar cfz $TARFILE SyncKit
rm $LINK
ln -s $TARFILE $LINK


echo WARNING: Changes to this SyncKit do not automatically propagate to DR git/nfs/cups servers, and will need to be manually coppied to servers where changes are required.
echo SyncKit saved to $BASE/$TARFILE

