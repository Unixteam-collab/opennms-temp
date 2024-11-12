#!/bin/bash


OPENNMS_BASE=/opt/opennms
CONFIG_DIR=${OPENNMS_BASE}/.ABBCS_Config_defaults
CONFIG_DEFAULTS=${CONFIG_DIR}/defaults

. $CONFIG_DEFAULTS

SOURCE_USER=rfoutages
DATA_DIR=/etc/testsvr.d/
WORK=$DATA_DIR/work

mkdir -p $WORK


if [ "$ALLOW_AUTOMATED_INSTALL" = "true" ]
then
   scp -o StrictHostKeyChecking=no $SOURCE_USER@$SOURCE_SERVER:${DATA_DIR}/* ${WORK}
   mv $WORK/* $DATA_DIR
fi


