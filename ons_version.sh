#/bin/bash

# 
#
# Program Name: ons_version.sh
#
# Purpose:  To manage opennms package version locks
#
#    OpenNMS version upgrades needs to be carefully managed, so yum-versionlock is used to prevent
#    accidental OpenNMS upgrade when OS patching is applied.  
#
#    Without parameters, lists the managed packages and their currently installed version, and locked status
#    
# Parameters:
#      -u  - Unlock the list of packages to allow patching
#      -l  - Lock packages to prevent accidental package upgrades
#
# Version: 1.4
#
# History: 2017-09-05  1.0  JDB  Initial Revision
#          2018-12-10  1.1  JDB  Added opennms-helm
#          2019-02-25  1.2  JDB  Added mssql-tools and msodbcsql17  because as of 25th Feb 2019, the latest version
#                                of msodbcsql17 is incompatible with the latest version of mssql-tools, and OS patcing
#                                fails due to incompatibility between the latest available versions of these 2 packages
#          2019-02-28 1.3   JDB  mssql-tools version incombatibility resolved.
#          2019-05-29 1.4   JDB  added opennms-source
#

PACKAGE_LIST="opennms
opennms-plugin-protocol-cifs
opennms-webapp-jetty
opennms-core
opennms-helm
opennms-source
grafana"
#mssql-tools
#msodbcsql17"
VERSION_LOCK_LIST="$(yum versionlock list | grep 0:)"

if [ $# == 0 ]
then
   echo Version Managed Packages
   
   for package in $PACKAGE_LIST
   do
      echo "  $package"
   done
   echo
   echo currently installed versions:
   for package in $PACKAGE_LIST
   do
      if rpm -q $package > /dev/null
      then
         IVERS=$(rpm -q $package)
         echo "  $IVERS"
      else 
         echo "   $package not installed"
      fi
   done
   echo
   echo Locked packages:
   for package in $VERSION_LOCK_LIST
   do
      echo "  $package"
   done

else
  case $1 in
    -u)
       echo unlocking
       yum versionlock delete $PACKAGE_LIST
       ;;
    -l)
       echo locking
       yum versionlock $PACKAGE_LIST
       ;;
    *)
       echo invalid parameter
       ;;
  esac
fi

