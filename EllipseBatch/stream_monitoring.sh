#!/bin/bash
#***************Stream monitoring by Sadish Nambiar - v1******************
# Creation date 10/09/2021
#
#***Config***
#Although this script can be used for all client that needs the stream monitored. The 
#processing is not straight forward therefore certain input files needs to be updated both on 
#Batch server and Opennms to ensure proper monitoring. 
#
#***History***
# This script is written to cater WPC stream monitoring which is initiated via control-m. 
# However the script can be also used for other clients which are using cyclic stream that
# runs out of the default overnight stream which need to complete on time. The logical 
# processing is done on the batch server and only the stats is grabbed by this script to 
# raise the alert.

TARGETDEVICEID1=$1       # Single CI to raise againts the alert which should be batch server
applianceHOST=$2         # Appliance hostname or IP
parms=/home/opennms/etc/parms_stream
currenttime=$(date +%H:%M)


	while IFS=, read -r -a input; do
	# printf "\n" "${input[0]}" "${input[1]}" "${input[2]}"

		if [[ "$currenttime" > "${input[1]}" ]] && [[ "$currenttime" < "${input[2]}" ]]; then
		#do_something

			response=$(ssh -nq opennms@"$applianceHOST" cat /home/opennms/stats )
			notify=$(echo "$response" | grep -i "${input[0]}" )
			status=$(echo "$notify" | awk -F, '{print $2}' )
			stream=$(echo "$notify" | awk -F, '{print $1}' )
			
			
				if [[ "$status" == 'NOTIFY' ]]; then
			
					string="There are no evidence found for STREAM $stream completion in batch log. PERFORM SANITY CHECK OF BATCH AND STREAM COMPLETION."
					message=$(echo $string)
					/opt/opennms/bin/send-event.pl uei.opennms.org/ABBCS/event -n $TARGETDEVICEID1 -d "Batch failure"  -p "message $message" -p "resourceId $stream" -p "category Ellipse" -x "7"
					
					echo " Issue detected with $stream ."
					
				else
					echo "Check success. Stream $stream completed."
				fi
				
	
		else
		#do_something_else
		echo "Sleep for now ${input[0]} untill ${input[1]}"

		fi


	done < $parms




