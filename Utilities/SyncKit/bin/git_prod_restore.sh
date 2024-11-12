#!/bin/bash
#
# Program: git_prod_restore.sh
#
# Version: 2.2
#
# Revision History:
#     1.0   Kuppa 2018-01-26 - Initial version
#     1.1   JohnB 2018-10-11 - Added cleanup of /var/opt/gitlab/git-data/repositories.old directories
#     2.0   JohnB 2018-10-12 - Modified to be client agnostic to work with SyncKit and added error checking
#     2.1   JohnB 2018-11-28 - Modified regexp for finding backup file name
#     2.2   JohnB 2018-12-13 - Cleanup backup directory on source after generating backup
##
# delete log files older than 7 days
# moved to log-rotate
#/usr/bin/find "/opt/scriptlogs/" -name "*.log" -mtime +7 -exec /bin/rm -f {} \;

SOURCE=$1
ENV=$2


# SSH AND CREATE BACKUP of GIT from production

backup_out=$(ssh $SOURCE "gitlab-rake gitlab:backup:create")
if [ $? != 0 ]
then 
   echo "$backup_out"
   echo "Backup failed"
   exit 1
fi

#EXTRACT TAR FILE NAME

#backupFile=$(echo $backup_out | grep -o -m 1 -E -e '[0-9]+_.*_gitlab_backup.tar' | cut -d ' ' -f1)
backupFile=$(echo $backup_out | grep -o -m 1 -E -e '[0-9]*_gitlab_backup.tar' | cut -d ' ' -f1)
echo "Backup file Name is: $backupFile"

#copy tar file to dest. Remove or Empty backup directory before copying. 
# This makes restore easy without having to specify backup name with only one file.
#

rm -f  /var/opt/gitlab/backups/*.tar
scp -p $SOURCE:/var/opt/gitlab/backups/$backupFile /var/opt/gitlab/backups/
if [ $? != 0 ]
then 
   echo "Transfer failed"
   exit 1
fi
# cleanup
ssh $SOURCE 'find /var/opt/gitlab/backups -name \*gitlab_backup.tar -type f -mtime +10 -exec rm {} \;'


# change OWNERSHIP OF BACKUP FILE TO GIT !! VERY IMPORTTANT
chown git:git /var/opt/gitlab/backups/$backupFile

#EXTRACT GIT BACKUP NAME - not required as we are removing previous backups.`
#gitBackupName=$(echo "$backupFile" |  grep -o '[0-9]\{1,\}')
#gitBackupName=$(echo "$backupFile" | cut -d '_' -f1)
#echo $gitBackupName

# STOP GITLAB

gitlab-ctl stop unicorn
gitlab-ctl stop sidekiq
service gitlab stop

# Verify
gitlab-ctl status

# PERFORM RESTORE
#gitlab-rake gitlab:backup:restore force=yes BACKUP=$gitBackupName
gitlab-rake gitlab:backup:restore force=yes RAILS_ENV=$ENV 

if [ $? != 0 ]
then 
   echo "Restore failed"
   exit 1
fi

# START GITLAB
gitlab-ctl start
gitlab-rake gitlab:check SANITIZE=true

# MANUALLY CHECK AND CORRECT APPLIANCE USER KEYS


# Cleanup old repositories

find /var/opt/gitlab/git-data -maxdepth 1 -name repositories.old.\* -mtime +7 -exec rm -rf {} \;

exit 0
