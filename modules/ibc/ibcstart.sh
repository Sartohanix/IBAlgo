#!/bin/bash


#==============================================================================
#
#                       PARSING & ERROR HANDLING
#
#==============================================================================


showUsage () {
	echo
	echo "Runs IBC, thus loading TWS or the IB Gateway"
	echo
	echo "Usage:"
	echo
	echo "ibcstart twsVersion [-g \| --gateway] [--tws-path=twsPath]"
	echo "             [--tws-settings-path=twsSettingsPath] [--ibc-path=ibcPath]"
	echo "             [--ibc-ini=ibcIni] [--java-path=javaPath]"
	echo "             [--user=userid] [--pw=password]"
	echo "             [--fix-user=fixuserid] [--fix-pw=fixpassword]"
	echo "             [--mode=tradingMode]"
	echo "             [--on2fatimeout=2fatimeoutaction]"
	echo
	echo "  twsVersion              The major version number for TWS"
	echo
	echo "  -g or --gateway         Indicates that the IB Gateway is to be loaded rather"
	echo "                          than TWS"
	echo
	echo "  twsPath                 Path to the TWS installation folder. Defaults to"
	echo "                          ~/Jts on Linux, ~/Applications on OS X"
	echo
	echo "  twsSettingsPath         Path to the TWS settings folder. Defaults to"
	echo "                          the twsPath argument"
	echo
	echo "  ibcPath                 Path to the IBC installation folder."
	echo "                          Defaults to /opt/ibc"
	echo
	echo "  ibcIni                  The location and filename of the IBC "
	echo "                          configuration file. Defaults to "
	echo "                          ~/ibc/config.ini"
	echo
	echo "  javaPath                Path to the folder containing the java executable to"
	echo "                          be used to run IBC. Defaults to the java"
	echo "                          executable included in the TWS installation; failing "
	echo "                          that, to the Oracle Java installation"
	echo
	echo "  userid                  IB account user id"
	echo
	echo "  password                IB account password"
	echo
	echo "  fixuserid               FIX account user id (only if -g or --gateway)"
	echo
	echo "  fixpassword             FIX account password (only if -g or --gateway)"
	echo
	echo "  tradingMode             Indicates whether the live account or the paper "
	echo "                          trading account will be used. Allowed values are:"
	echo
	echo "                              live"
	echo "                              paper"
	echo
	echo "                          These values are not case-sensitive."
	echo
	echo "  2fatimeoutaction       Indicates what to do if IBC exits due to second factor"
	echo "                         authentication timeout. Allowed values are:"
	echo
	echo "                              restart"
	echo "                              exit"
	echo
}

if [[ "$1" = "" || "$1" = "-?" || "$1" = "-h" || "$1" = "--HELP" ]]; then
	showUsage
	exit 0
fi

error_exit() {
	error_number=$1
	error_message=$2
	error_message1=$3
	error_message2=$4
	>&2 echo
	>&2 echo =========================== An error has occurred =============================
	>&2 echo
	>&2 echo
	>&2 echo
	>&2 echo -e "Error: ${error_message}"
	if [[ -n "${error_message1}" ]]; then
		>&2 echo -e "       ${error_message1}"
	fi
	if [[ -n "${error_message2}" ]]; then
		>&2 echo -e "       ${error_message2}"
	fi
	>&2 exit "${error_number}"
}


# Some constants

E_NO_JAVA=1
E_NO_TWS_VERSION=2
E_INVALID_ARG=3
E_TWS_VERSION_NOT_INSTALLED=4
E_IBC_PATH_NOT_EXIST=5
E_IBC_INI_NOT_EXIST=6
E_TWS_VMOPTIONS_NOT_FOUND=7
E_UNKNOWN_OPERATING_SYSTEM=8

# errorlevel set by IBC if second factor authentication dialog times out and
# ExitAfterSecondFactorAuthenticationTimeout setting is true
let E_2FA_DIALOG_TIMED_OUT=$((1111 % 256))

# errorlevel set by IBC if login dialog is not displayed within the time
# specified in the LoginDialogDisplayTimeout setting
E_LOGIN_DIALOG_DISPLAY_TIMEOUT=$((1112 % 256))

program=Gateway
entry_point=ibcalpha.ibc.IbcGateway

shopt -s nocasematch


# TO IMPLEMENT:
#
# 1. Set the variables:
	# tws_path
	# tws_settings_path
	# ibc_path
	# ibc_ini
	# java_path
	# ib_user_id
	# ib_password
	# mode
	# twofa_to_action
	# tws_version

# 2.a. Check mode is either LIVE or TRADING
# 2.b. Check twofa_to_action is either RESTART or EXIT

# Set the variables:
	# program_path="${gateway_program_path}"
	# vmoptions_source="${program_path}/ibgateway.vmoptions"
	# jars="${program_path}/jars"
	# install4j="${program_path}/.install4j"


#======================== Check everything ready to proceed ================

if [ "$tws_version" = "" ]; then
	error_exit $E_NO_TWS_VERSION "TWS major version number has not been supplied"
fi
	
if [[ ! -e "$jars" ]]; then
	error_exit $E_TWS_VERSION_NOT_INSTALLED "Offline TWS/Gateway version $tws_version is not installed: can't find jars folder" \
	                                        "Make sure you install the offline version of TWS/Gateway" \
                                            "IBC does not work with the auto-updating TWS/Gateway"
fi

if [[ ! -e  "$ibc_path" ]]; then
	error_exit $E_IBC_PATH_NOT_EXIST "IBC path: $ibc_path does not exist"
fi

if [[ ! -e "$ibc_ini" ]]; then
	error_exit $E_IBC_INI_NOT_EXIST "IBC configuration file: $ibc_ini  does not exist"
fi

if [[ ! -e "$vmoptions_source" ]]; then
	error_exit $E_TWS_VMOPTIONS_NOT_FOUND "Neither tws.vmoptions nor ibgateway.vmoptions could be found"
fi

if [[ -n "$java_path" ]]; then
	if [[ ! -e "$java_path/java" ]]; then
		error_exit $E_NO_JAVA "Java installaton at $java_path/java does not exist"
	fi
fi


echo =================================

echo Generating the classpath

for jar in "${jars}"/*.jar; do
	if [[ -n "${ibc_classpath}" ]]; then
		ibc_classpath="${ibc_classpath}:"
	fi
	ibc_classpath="${ibc_classpath}${jar}"
done
ibc_classpath="${ibc_classpath}:$install4j/i4jruntime.jar:${ibc_path}/IBC.jar"

echo -e "Classpath=$ibc_classpath"
echo

#======================== Generate the JAVA VM options =====================

echo Generating the JAVA VM options

declare -a vm_options
index=0
while read line; do
	if [[ -n ${line} && ! "${line:0:1}" = "#" && ! "${line:0:2}" = "-D" ]]; then
		vm_options[$index]="$line"
		((index++))
	fi
done <<< $(cat ${vmoptions_source})

java_vm_options=${vm_options[*]}
java_vm_options="$java_vm_options -Dtwslaunch.autoupdate.serviceImpl=com.ib.tws.twslaunch.install4j.Install4jAutoUpdateService"
java_vm_options="$java_vm_options -Dchannel=latest"
java_vm_options="$java_vm_options -Dexe4j.isInstall4j=true"
java_vm_options="$java_vm_options -Dinstall4jType=standalone"
java_vm_options="$java_vm_options -DjtsConfigDir=${tws_settings_path}"

ibc_session_id=$(mktemp -u XXXXXXXX)
java_vm_options="$java_vm_options -Dibcsessionid=$ibc_session_id"


find_auto_restart() {
	local autorestart_path=""
	local f=""
	restarted_needed=
	for i in $(find $tws_settings_path -type f -name "autorestart"); do
		local x=${i/$tws_settings_path/}
		local y=$(echo $x | xargs dirname)/.
		local e=$(echo "$y" | cut -d/ -f3)
		if [[ "$e" = "." ]]; then
			if [[ -z $f ]]; then
				f="$i"
				echo "autorestart file found at $f"
				autorestart_path=$(echo "$y" | cut -d/ -f2)
			else
				autorestart_path=
				echo "WARNING: deleting extra autorestart file found at $i"
				rm $i
				echo "WARNING: deleting first autorestart file found"
				rm $f
			fi
		fi
	done

	if [[ -z $autorestart_path ]]; then
		if [[ -n $f ]]; then
			echo "*******************************************************************************"
			echo "WARNING: More than one autorestart file was found. IBC can't determine which is"
			echo "         the right one, so they've all been deleted. Full authentication will"
			echo "         be required."
			echo
			echo "         If you have two or more TWS/Gateway instances with the same setting"
			echo "         for TWS_SETTINGS_PATH, you should ensure that they are configured with"
			echo "         different autorestart times, to avoid creation of multiple autorestart"
			echo "         files."
			echo "*******************************************************************************"
			echo
			restarted_needed=yes
		else 
			echo "autorestart file not found"
			echo
			restarted_needed=
		fi
	else
		echo "AUTORESTART_OPTION is -Drestart=${autorestart_path}"
		autorestart_option=" -Drestart=${autorestart_path}"
		restarted_needed=yes
	fi
}

find_auto_restart

echo -e "Java VM Options=$java_vm_options$autorestart_option"
echo

#======================== Determine the location of java executable ========

echo Determining the location of java executable

# Read a path from config file. If it contains a java executable,
# return the path to the executable. Return an empty string otherwise.
function read_from_config {
	path=$1
	if [[ -e "$path" ]]; then
		read java_path_from_config < "$path"
		if [[ -e "$java_path_from_config/bin/java" ]]; then
			echo -e "$java_path_from_config/bin"
		else
			>&2 echo -e "Could not find $java_path_from_config/bin/java"
			echo ""
		fi
	else
		echo ""
	fi
}

if [[ ! -n "$java_path" ]]; then
	java_path=$(read_from_config "$install4j/pref_jre.cfg")
fi
if [[ ! -n "$java_path" ]]; then
	java_path=$(read_from_config "$install4j/inst_jre.cfg")
fi

if [[ -z "$java_path" ]]; then
	error_exit $E_NO_JAVA "Can\'t find suitable Java installation"
elif [[ ! -e "$java_path/java" ]]; then
	error_exit $E_NO_JAVA "No java executable found in supplied path $java_path"
fi

echo Location of java executable=$java_path
echo

#======================== Start IBC ===============================

got_api_credentials=1
hidden_credentials="*** ***"

# prevent other Java tools interfering with IBC
JAVA_TOOL_OPTIONS=

pushd "$tws_settings_path" > /dev/null

echo "Renaming IB's TWS or Gateway start script to prevent restart without IBC"
if [[ -e "${program_path}/ibgateway" ]]; then mv "${program_path}/ibgateway" "${program_path}/ibgateway1"; fi
echo

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

echo "$program finished"
echo

popd > /dev/null

exit $exit_code


