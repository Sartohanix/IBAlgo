#!/bin/bash

program=Gateway
entry_point=ibcalpha.ibc.IbcGateway

java_path="$l_dir/jre"
jars="$l_dir/jars"

ibc_classpath=

for jar in "${jars}"/*.jar; do
	if [[ -n "${ibc_classpath}" ]]; then
		ibc_classpath="${ibc_classpath}:"
	fi
	ibc_classpath="${ibc_classpath}${jar}"
done
ibc_classpath="${ibc_classpath}:$install4j/i4jruntime.jar:${ibc_path}/IBC.jar"

# Main loop
while :; do
	echo "Starting $program with this command:"
	echo -e "\"$java_path/java\" -cp \"$ibc_classpath\" $java_vm_options$autorestart_option $entry_point \"$ibc_ini\" $hidden_credentials ${mode}"
	echo

	# forward signals (see https://veithen.github.io/2014/11/16/sigterm-propagation.html)
	trap 'kill -TERM $PID' TERM INT

	"$java_path/java" -cp "$ibc_classpath" $java_vm_options$autorestart_option $entry_point "$ibc_ini" "$ib_user_id" "$ib_password" ${mode} &

	PID=$!
	wait $PID
	trap - TERM INT
	wait $PID

	exit_code=$(($? % 256))
	echo "IBC returned exit status $exit_code"

	if [[ $exit_code -eq $E_LOGIN_DIALOG_DISPLAY_TIMEOUT ]]; then 
		:
	elif [[ -e "$tws-settings-path/COLDRESTART$ibc_session_id" ]]; then
		rm "$tws-settings-path/COLDRESTART$ibc_session_id"
		autorestart_option=
		echo "IBC will cold-restart shortly"
	else
		find_auto_restart
		if [[ -n $restarted_needed ]]; then
			restarted_needed=
			# restart using the TWS/Gateway-generated autorestart file
			:
		elif [[ $exit_code -ne $E_2FA_DIALOG_TIMED_OUT  ]]; then 
			break;
		elif [[ ${twofa_to_action_upper} != "RESTART" ]]; then 
			break; 
		fi
	fi
	
	# wait a few seconds before restarting
	echo IBC will restart shortly
	echo sleep 2
done