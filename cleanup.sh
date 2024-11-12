#!/bin/bash


cleanup()
{
MINCOUNT=$1
FILES=$(ls -t1 $2 )

DELETERS=""
COUNT=1
echo "$FILES" |  while read FILE
do
  if [ $COUNT -gt $MINCOUNT ]
  then
     echo got one to delete
     /bin/rm "$FILE"
     DELETERS="$DELETERS $FILE"
  fi
  COUNT=$((COUNT + 1 ))
done

if [ "X$DELETERS" != "X" ]
then 
  echo files deleted $DELETERS 
else
  echo nothing to delete
fi
}

cleanup_rrd()
{
MAXAGE=$1
FILES="$2"

for DIR in $FILES
do
   COUNT=$(find $DIR -mtime -$MAXAGE | wc -l)
   if [ $COUNT = 0 ]
   then
      echo Found old RRD directory $DIR.  Deleting
      /bin/rm -rf "$DIR"
   fi
done
}

cleanup 20 '/opt/opennms_save_config/ABBCS*.tgz'
cleanup 20 '/opt/opennms_save_config/ABBCS*.x'
cleanup 8 '/opt/opennms_save_config/backups/local*.tgz'
cleanup 2 '/opt/opennms_config_stage/ABBCS*.tgz'
cleanup 2 '/opt/opennms_config_stage/ABBCS*.x'
cleanup 10 '/opt/opennms/scripts/Utilities/*.tgz'

# clean up from old backup configuration  (backups have been moved to sub directories per OpenNMS server name
# keep 4 more than is saved on remote opennms servers to try and stop remote from re-uploading already deleted files
/bin/rm -f /home/opennms/backups/*.tgz
for i in $(ls -d /home/opennms/backups/*) 
do
  echo $i
  cleanup 10 "$i"'/local*.tgz'
done

# cleanup RRD directories that contain no recent updated statistics 
cleanup_rrd 180 '/opt/opennms/share/rrd/snmp/fs/*'
cleanup_rrd 180 '/opt/opennms/share/rrd/snmp/[0-9]*'
cleanup_rrd 180 '/opt/opennms/share/rrd/response/*'

exit


