#!/bin/bash

# ./URL_Test.sh 10.165.6.134 '/ria/bind?app=login' 'invalid.credentials' 30 'Ellipse_Login'

XML_ENCODE=/opt/opennms/scripts/Utilities/xml_encoder.sh


HOST=$1
URI="$($XML_ENCODE "$2")"
SEARCH=$3
TIMEOUT=$4
PAGE=$5

HOME=/opt/opennms/scripts/Utilities/URL_Tester
CONFIG=$HOME/etc
ETC=/home/opennms/etc
WORKING=/home/opennms/var
LOGDIR=/home/opennms/logs/$HOST

if [ ! -d $LOGDIR ]
then
   mkdir -p $LOGDIR
   mv $LOGDIR/../URL_Test*${HOST}* $LOGDIR
fi


XML="@${CONFIG}/${PAGE}.xml"
XMLTMP=${WORKING}/URL_Test_${PAGE}_${HOST}.xml
XMLOUT=${ETC}/URL_Test_${PAGE}_${HOST}.xml

LOG=${LOGDIR}/URL_Test_${PAGE}_${HOST}.log
ERR=${LOGDIR}/URL_Test_${PAGE}_${HOST}.err

date >> $LOG
date >> $ERR

#XML='<interaction><actions><action><name>loginEncoded</name><data><username>ABB_Monitoring</username><password>qTImqN==</password><scope/><position/><rememberMe>N</rememberMe></data><id>51153065-1428-7716-3474-999805BE53AB</id></action></actions><chains/><application>login</application><applicationPage/></interaction>'


RESULT=$(curl -v -m $TIMEOUT -w "\ntime_total=%{time_total}\n" -X POST -d "$XML" -k --header 'Content-Type:application/xml;charset=UTF-8' 'https://'$HOST$URI 2>>$ERR)

echo HOST = $HOST >> $LOG
echo URI = $URI >> $LOG
echo \$2 = $2 >> $LOG
echo SEARCH = $SEARCH >> $LOG
echo TIMEOUT = $TIMEOUT >> $LOG
echo PAGE = $PAGE >> $LOG

echo CMD= $CMD >> $LOG
echo RESULT: >> $LOG
echo $RESULT >> $LOG

#time_namelookup=%{time_namelookup}\n
#time_connect=%{time_connect}\n
#time_appconnect=%{time_appconnect}\n
#time_pretransfer=%{time_pretransfer}\n
#time_redirect=%{time_redirect}\n
#time_starttransfer=%{time_starttransfer}\n
#time_total=%{time_total}\n

if [[ $RESULT =~ ${SEARCH} ]]
then
   echo Got match >> $LOG
   FOUND=1
else
   echo no match >> $LOG
   FOUND=0
fi

eval $(echo "$RESULT" | tail -1)

cat > $XMLTMP <<EOF
<URL_Test page="$PAGE">
    <host>$HOST</host>
    <URI>$URI</URI>
    <SUCCESS>$FOUND</SUCCESS>
    <TIME>$time_total</TIME>
</URL_Test>
EOF

mv $XMLTMP $XMLOUT
