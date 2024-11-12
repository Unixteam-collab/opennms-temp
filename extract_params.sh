#!/bin/bash

# This script was created to extract parameters passed to event capture on STDIN
# it was found that OpenNMS puts single quotes in some of the parameters, which was breaking parameter extraction
#
# This script assumes that parameters with values not enclosed in quotes are 1st followed by RESOURCEID followed by the rest which always are enclosed in quotes.
#
# if additional parameters are required, they will need to be included here
# use the following command to find all parameters that need to be handled:
#grep = notifications.xml  | grep -v status | grep -v text | grep -v rule | grep -v xmlns| cut -d= -f1 | sort -u
#
# Current list of handled variables:
#CATEGORY
#EVENTID
#eventReason
#LABEL
#MESSAGE
#NOTICEID
#OPERATORINSTRUCT
#OTHERPARAMS
#RESOURCEID
#SERVICE
#SEVERITY
#THRESHOLD


PFILE=$1

> $PFILE

while read line
do
   VAR=$(echo "$line" | cut  -d= -f 1)
   REST=$(echo "$line" | cut -d= -f 2- | tr -d \'\\& )
 


 

   case $VAR in 
     NODE|NOTICEID|SERVICE|SEVERITY|EVENTID|CATEGORY)
        /bin/echo "$VAR=$REST" >> $PFILE
        ;;
     RESOURCEID)
        /bin/echo -n "$VAR='$REST" >> $PFILE
        ;;
     LABEL|THRESHOLD|OTHERPARAMS|OPERATORINSTRUCT|MESSAGE|eventReason)
        /bin/echo -n "'
$VAR='$REST" >> $PFILE
        ;;
     *)
        /bin/echo -n "
$line" | tr -d  \'\\&   >> $PFILE
     esac 

done
/bin/echo "'
" >> $PFILE
