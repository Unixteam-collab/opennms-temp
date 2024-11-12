#!/bin/bash

for i in psql clusterdb createdb createuser dropdb dropuser pg_basebackup pg_dump pg_dumpall pg_restore reindexdb vacuumdb
do
   mv /usr/bin/$i /usr/bin/$i.v9
   ln -s /etc/alternatives/pgsql-$i /usr/bin/$i
done
