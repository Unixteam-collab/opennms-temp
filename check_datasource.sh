#!/bin/bash

# Check opennms-datasources.xml, and if it is the original file, then replace it with one containing default customisations.
# This is so we can deploy a customised opennms-datasources.xml file with the skeleton for Oracle Database connection pools
#   allowing DBA's to customise the opennms-datasources.xml file without fear of install-customisation script blowing away the changes

OPENNMS_HOME=/opt/opennms

DS_FILE=${OPENNMS_HOME}/etc/opennms-datasources.xml
DS_ORIG=${OPENNMS_HOME}/share/etc-pristine/opennms-datasources.xml
DS_CUSTOM=${OPENNMS_HOME}/.ABBCS_Config_defaults/default-opennms-datasources.xml

diff $DS_FILE $DS_ORIG  > /dev/null 2>&1

RES=$?

echo $RES
if [ $RES == 0 ]
then
   cp $DS_CUSTOM $DS_FILE
fi
