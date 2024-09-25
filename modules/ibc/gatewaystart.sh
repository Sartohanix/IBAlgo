#!/bin/bash

################## Settings ##################

TWS_MAJOR_VRSN=
IBC_INI=

IBC_PATH=
TWS_PATH=
TWS_SETTINGS_PATH=
LOG_PATH=

TRADING_MODE=
TWOFA_TIMEOUT_ACTION=

TWSUSERID=
TWSPASSWORD=
FIXUSERID=
FIXPASSWORD=
JAVA_PATH=
HIDE=

##############################################


# Function to display help message
display_help() {
    printf "Usage: %s {start|start-nogui|status|stop|help} [OPTIONS]\n" "$0"
    printf "\nCommands:\n"
    printf "  start         Starts the Gateway in the background with GUI\n"
    printf "  start-nogui   Starts the Gateway in the background without GUI\n"
    printf "  status        Displays whether the Gateway is running and its PID if found\n"
    printf "  stop          Stops the Gateway if it is running\n"
    printf "  help          Displays this help message\n"
    printf "\nOptions:\n"
    printf "  --log-to-file             Enables logging to an automatically created log file\n"
    printf "  --display-id <id>         Sets the display ID for the Xvfb server (default: 9)\n"
    printf "  --force-xvfb-restart, -f  Forces restart of the Xvfb server if already running\n"
}

# Parse command line arguments
LOG_TO_FILE=false
COMMAND=""
DISPLAY_ID=9
FORCE_RESTART=false

while [[ $# -gt 0 ]]; do
    case $1 in
        start|start-nogui|status|stop|help)
            COMMAND=$1
            shift
            ;;
        --log-to-file)
            LOG_TO_FILE=true
            shift
            ;;
        --display-id)
            DISPLAY_ID="$2"
            shift 2
            ;;
        --force-xvfb-restart|-f)
            FORCE_RESTART=true
            shift
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            display_help
            exit 1
            ;;
    esac
done

# Check if a valid command was provided
if [ -z "$COMMAND" ]; then
    echo "Error: No command provided" >&2
    display_help
    exit 1
fi

APP=GATEWAY

# Export Variables
export TWS_MAJOR_VRSN
export IBC_INI
export TRADING_MODE
export TWOFA_TIMEOUT_ACTION
export IBC_PATH
export TWS_PATH
export TWS_SETTINGS_PATH
export TWSUSERID
export TWSPASSWORD
export FIXUSERID
export FIXPASSWORD
export JAVA_PATH
export APP

# Function to check if the gateway process is running
gateway_pid() {
    /usr/bin/pgrep -f "java.*${IBC_INI}"
}

# Function to start the Gateway in the background with GUI
start_gateway() {
    if [[ -n $(gateway_pid) ]]; then
        printf "Gateway is already running (PID: %s).\n" "$(gateway_pid)"
        exit 0
    fi

    gw_flag="--gateway"

    if [[ -x "${IBC_PATH}/scripts/ibcstart.sh" ]]; then
        # get the IBC version
        read IBC_VRSN < "${IBC_PATH}/version"

        LOG_PATH=${IBC_PATH}/logs

        # Set up logging
        if $LOG_TO_FILE; then
            if [[ ! -e "$LOG_PATH" ]]; then
                mkdir -p "$LOG_PATH"
            fi
            readme=${LOG_PATH}/README.txt
            if [[ ! -e "$readme" ]]; then
                echo You can delete the files in this folder at any time > "$readme"
                echo >> "$readme"
                echo "You'll be informed if a file is currently in use." >> "$readme"
            fi
            LOG_FILE=${LOG_PATH}/ibc-${IBC_VRSN}_${APP}-${TWS_MAJOR_VRSN}_$(date +%A).txt
            if [[ -e "$LOG_FILE" ]]; then
                if [[ $(uname) = [dD]arwin* ]]; then
                    if [[ $(stat -f "%Sm" -t %D "$LOG_FILE") != $(date +%D) ]]; then rm "$LOG_FILE"; fi
                else
                    if [[ $(date -r "$LOG_FILE" +%D) != $(date +%D) ]]; then rm "$LOG_FILE"; fi
                fi
            fi
        else
            LOG_FILE=/dev/null
        fi

        # Print startup information
        normal='\033[0m'
        light_green='\033[1;32m'
        echo -e "${light_green}+=============================================================================="
        echo "+"
        echo -e "+ IBC version ${IBC_VRSN}"
        echo "+"
        echo -e "+ Running ${APP} ${TWS_MAJOR_VRSN}"
        echo "+"
        if [[ "$LOG_FILE" != "/dev/null" ]]; then
            echo "+ Diagnostic information is logged in:"
            echo "+"
            echo -e "+ ${LOG_FILE}"
            echo "+"
        fi
        echo -e "+${normal}"

        if [[ "$(echo ${APP} | tr '[:lower:]' '[:upper:]')" = "GATEWAY" ]]; then
            gw_flag=-g
        fi

        export IBC_VRSN

        if $LOG_TO_FILE; then
            (
                "${IBC_PATH}/scripts/ibcstart.sh" "${TWS_MAJOR_VRSN}" ${gw_flag} \
                    "--tws-path=${TWS_PATH}" "--tws-settings-path=${TWS_SETTINGS_PATH}" \
                    "--ibc-path=${IBC_PATH}" "--ibc-ini=${IBC_INI}" \
                    "--user=${TWSUSERID}" "--pw=${TWSPASSWORD}" "--fix-user=${FIXUSERID}" "--fix-pw=${FIXPASSWORD}" \
                    "--java-path=${JAVA_PATH}" "--mode=${TRADING_MODE}" "--on2fatimeout=${TWOFA_TIMEOUT_ACTION}"
            ) >> "${LOG_FILE}" 2>&1 &
        else
            "${IBC_PATH}/scripts/ibcstart.sh" "${TWS_MAJOR_VRSN}" ${gw_flag} \
                "--tws-path=${TWS_PATH}" "--tws-settings-path=${TWS_SETTINGS_PATH}" \
                "--ibc-path=${IBC_PATH}" "--ibc-ini=${IBC_INI}" \
                "--user=${TWSUSERID}" "--pw=${TWSPASSWORD}" "--fix-user=${FIXUSERID}" "--fix-pw=${FIXPASSWORD}" \
                "--java-path=${JAVA_PATH}" "--mode=${TRADING_MODE}" "--on2fatimeout=${TWOFA_TIMEOUT_ACTION}"
        fi

        printf "Gateway started in the background (PID: %s).\n" "$!"
    else
        printf "Error: no execute permission for scripts in %s/scripts\n" "${IBC_PATH}" >&2
        exit 1
    fi
}

# Function to start the Gateway in the background without GUI
start_gateway_nogui() {
    # Parse command line arguments for nogui start
    while [[ $# -gt 0 ]]; do
        case $1 in
            --display-id)
            DISPLAY_ID="$2"
            shift 2
            ;;
            --force-xvfb-restart|-f)
            FORCE_RESTART=true
            shift
            ;;
            *)
            echo "Error: Unknown option '$1' for start-nogui" >&2
            display_help
            exit 1
            ;;
        esac
    done

    # Path to xvfb-function script
    XVFB_SERVER_SCRIPT="./scripts/xvfb/xvfb-functions.sh"

    # Check if xvfb-function script exists
    if [ ! -f "$XVFB_SERVER_SCRIPT" ]; then
        echo "Error: xvfb-function script not found at $XVFB_SERVER_SCRIPT"
        exit 1
    fi

    # Function to start xvfb server
    start_xvfb_server() {
        "$XVFB_SERVER_SCRIPT" start "$DISPLAY_ID"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to start Xvfb server on display :$DISPLAY_ID"
            exit 1
        fi
    }

    # Check if xvfb server is already running
    if xdpyinfo -display :$DISPLAY_ID >/dev/null 2>&1; then
        if [ "$FORCE_RESTART" = true ]; then
            echo "Stopping existing Xvfb server on display :$DISPLAY_ID"
            "$XVFB_SERVER_SCRIPT" stop "$DISPLAY_ID"
            start_xvfb_server
        else
            echo "Error: Xvfb server is already running on display :$DISPLAY_ID"
            echo "Use --force-xvfb-restart or -f to force restart the server"
            exit 1
        fi
    else
        start_xvfb_server
    fi

    # Set DISPLAY environment variable
    export DISPLAY=:$DISPLAY_ID

    # Start the Gateway without GUI
    start_gateway
}

# Function to check the status of the Gateway
status_gateway() {
    local pid
    pid=$(gateway_pid)
    if [[ -n "$pid" ]]; then
        printf "Gateway is running (PID: %s).\n" "$pid"
        
        # Check if the gateway was started with Xvfb (nogui mode)
        if ps -p "$pid" -o cmd= | grep -q "DISPLAY=:"; then
            display_id=$(ps -p "$pid" -o cmd= | grep -oP 'DISPLAY=:\K\d+')
            printf "Started in nogui mode (Xvfb Display ID: %s)\n" "$display_id"
        else
            printf "Started in GUI mode\n"
        fi
    else
        printf "Gateway is not running.\n"
    fi
}

Cop

# Function to stop the Gateway
stop_gateway() {
    local pid
    pid=$(gateway_pid)
    if [[ -n "$pid" ]]; then
        kill -SIGTERM "$pid"
        printf "Gateway stopped (PID: %s).\n" "$pid"
    else
        printf "No Gateway process is running.\n"
    fi
}

# Main logic for handling arguments
case "$COMMAND" in
    start)
        start_gateway
        ;;
    start-nogui)
        start_gateway_nogui "$@"
        ;;
    status)
        status_gateway
        ;;
    stop)
        stop_gateway
        ;;
    help)
        display_help
        ;;
    *)
        printf "Invalid command: %s\n" "$COMMAND"
        display_help
        exit 1
        ;;
esac
