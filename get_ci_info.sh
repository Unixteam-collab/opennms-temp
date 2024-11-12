#!/bin/bash


NAME=none
IP=none
NEXTISIF=false

/opt/opennms/bin/provision.pl list | tr -d '()'| while read a b c d e f g
do
   # Look for ID
   if [ "$d" = 'ID:' ]
   then
      if [ "$NAME" != 'none' ]
      then
        echo $NAME  $IP
      fi
      NAME="$e"
   fi

   #check if this line has been flagged as an IP address
   if [ $NEXTISIF = 'true' ]
   then
      NEXTISIF='false'
      IP=$b
   fi 

   # look for "interfaces" in the line and if so flag that the next line will be an interface
   if [ "$b" = 'interfaces:' ]
   then
      NEXTISIF=true
   fi
   
done
