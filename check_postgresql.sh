#!/bin/bash

EXTREPO=pgdg15
LOCAL_MIRROR="ol7_x86_64_postgresql15"
PGINSTALLED="/opt/opennms/.ABBCS_Config_defaults/postgresql15.installed"


if [ -f $PGINSTALLED ]
then
   echo PostgreSQL 15 already configured.
else
   PSQLV=$(psql --version | cut -d \  -f 3 | cut -d. -f 1)

   echo Installing PostgreSQL 15
 
   # check repo config.
   yum repolist | grep $LOCAL_MIRROR > /dev/null 2>&1

   if [ $? != 0 ]
   then
      ENABLE_PG_REPO="--enablerepo=$EXTREPO"
   else
      ENABLE_PG_REPO=''
   fi

   yum $ENABLE_PG_REPO install -y --nogpgcheck postgresql15-server
   
   if [ $? != 0 ]
   then
      echo Failure to install Postgresql 15 - ABORTING
      exit 1
   fi
   
   echo extracting LC_CTYPE
   LANG="en_US.UTF-8"
   #systemctl start postgresql-11
   #LANG=$(echo $(su postgres -c 'psql -c "show lc_ctype"' | head -3 | tail -1))
   #echo got $LANG
   #systemctl stop postgresql-11
   PGSETUP_INITDB_OPTIONS=--locale=$LANG
   export PGSETUP_INITDB_OPTIONS
   echo cleanout pg data dir
   mv /var/lib/pgsql/15/data /var/lib/pgsql/15/data.orig
   echo initializing new db
   /usr/pgsql-15/bin/postgresql-15-setup initdb


   echo return value $?
 
   if [ "$PSQLV" -lt 15 ]
   then

      echo Migrating to PostgreSQL 15
      #DBLOC=$(su - postgres -c "pg_ctl status" | tail -1 | cut -d \"  -f 4)
      SOURCE=$(systemctl show -p Environment postgresql-11 |sed 's/^Environment=//' | tr ' ' '\n' |sed -n 's/^PGDATA=//p' | tail -n 1)
      DEST=/var/lib/pgsql/15/data
      echo ensuring postgresql is down
      su postgres -c "/usr/pgsql-11/bin/pg_ctl -D $SOURCE stop"
      su postgres -c "/usr/pgsql-15/bin/pg_ctl -D $DEST stop"

      echo everything should be down by now
      echo PSQLV = $PSQLV
      echo about to do datamigration
      echo su - postgres -c '/usr/pgsql-15/bin/pg_upgrade --old-datadir "'$SOURCE'"  --new-datadir "'$DEST'" --old-bindir "/usr/pgsql-11/bin" --new-bindir "/usr/pgsql-15/bin"'
      su - postgres -c '/usr/pgsql-15/bin/pg_upgrade --old-datadir "'$SOURCE'"  --new-datadir "'$DEST'" --old-bindir "/usr/pgsql-11/bin" --new-bindir "/usr/pgsql-15/bin"'

      echo disabling old version of postgresql
      systemctl disable postgresql-11

      yum -y remove postgresql11 postgresql11-server postgresql11-libs
      # restore postgresql-11 bash_profile removed by previous yum remove command
      cp /var/lib/pgsql/.bash_profile.rpmsave /var/lib/pgsql/.bash_profile


   fi

   echo enabling postgresql 15
   systemctl enable postgresql-15.service
   echo starting postgresql 15
   systemctl start postgresql-15.service
   echo analyzing new cluster
   su - postgres -c "/usr/pgsql-15/bin/vacuumdb --all --analyze-in-stages"
   echo set opennms db user password
   su - postgres -c "psql -c \"ALTER USER opennms WITH PASSWORD 'qq7aaY96WRqmdpckvtaJCpI36whSeN';
ALTER USER postgres WITH PASSWORD 'qq7aaY96WRqmdpckvtaJCpI36whSeN';\""

   rpm -q postgresql15
   if [ $? = 0 ]
   then
      echo PostgreSQL 15 installed
      ps -ef | grep [p]ostgre
      if [ $? = 0 ]
      then
         echo PostgreSQL 15 running\; installation and configuration appears to have succeeded
         touch $PGINSTALLED
      else
         echo PostgreSQL 15 not running\; configuration failure
         exit 1
      fi
   else
      echo PostgreSQL 15 not installed\; installation failure
      exit 1
   fi
fi

