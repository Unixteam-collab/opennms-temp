#!/bin/bash

# OpenNMS config changed to store RRD data in fs/<ForeignSource>/<ForeignID> to assist saving and restoring Performance metrics

RRDPATH=/var/opennms/rrd/snmp

# $WORK is only defined in install_customisations.sh when installing updates

. ${WORK}/opt/opennms/.ABBCS_Config_defaults/.opennms.creds

if [ ! -d "$RRDPATH/fs" ]
then
   mkdir -p $RRDPATH/fs
fi

curl http://$ONSUSER:$ONSPWD@localhost:8980/opennms/rest/nodes\?limit=0 2> /dev/null | xmllint --format - | grep foreign | while read extra fi fs lb id ty
do

  FOREIGNID=$(echo $fi | cut -d\" -f2)
  FOREIGNSOURCE=$(echo $fs | cut -d\" -f2)
  ID=$(echo $id | cut -d\" -f2)

  #echo ID=$ID
  #echo FOREIGNID=$FOREIGNID
  #echo FOREIGNSOURCE=$FOREIGNSOURCE

  if [ ! -d "$RRDPATH/fs/$FOREIGNSOURCE" ]
  then
    mkdir "$RRDPATH/fs/$FOREIGNSOURCE"
  fi

  if [ ! -d "$RRDPATH/fs/$FOREIGNSOURCE/$FOREIGNID" ]
  then
     if [ -d "$RRDPATH/$ID" ]
     then
        mv "$RRDPATH/$ID" "$RRDPATH/fs/$FOREIGNSOURCE/$FOREIGNID"
     fi
  fi

done

