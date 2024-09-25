#!/bin/bash

# Define the xvfb-functions command
xvfb-functions() {
    # Helper function to print usage
    usage() {
        echo "Usage: xvfb-functions [start|stop|list] [display_number]"
        echo "  start [display_number]: Start an Xvfb server on the specified display (default: :1)"
        echo "  stop [display_number]: Stop the Xvfb server on the specified display (default: :1)"
        echo "  list: List all running Xvfb servers"
        echo "  -h, --help: Show this help message"
    }

    # Command to start Xvfb
    start_xvfb() {
        local display_number="${1:-1}"

        # Check if the Xvfb server is already running on this display
        if pgrep -f "Xvfb :$display_number" > /dev/null; then
            echo "Xvfb server is already running on display :$display_number."
        else
            echo "Starting Xvfb server on display :$display_number with default geometry 1024x768 and depth 24..."
            Xvfb :$display_number -screen 0 1024x768x24 &
        fi
    }

    # Command to stop Xvfb
    stop_xvfb() {
        local display_number="${1:-1}"

        # Find the Xvfb process and kill it
        local xvfb_pid=$(pgrep -f "Xvfb :$display_number")

        if [[ -n "$xvfb_pid" ]]; then
            echo "Stopping Xvfb server on display :$display_number (PID: $xvfb_pid)..."
            kill "$xvfb_pid"
        else
            echo "No Xvfb server running on display :$display_number."
        fi
    }

    # Command to list running Xvfb servers
    list_xvfb() {
        echo "Listing all running Xvfb servers..."
        ps -ef | grep -v grep | grep Xvfb
    }
	
	# Function to get the window tree for a given display ID
	get_window_tree() {
		local display_id=$1
		local output=""

		# Stack to keep track of the remaining children at each depth level
		declare -a child_stack=()

		# Function to append a line with proper indentation to the output
		append_with_indent() {
			local depth_level=$1
			local content=$2
			output+=$(printf "%$((depth_level * 4))s%s\n" "" "$content")
		}

		# Function to decrement the depth when no more children are present
		pop_stack() {
			while [[ ${#child_stack[@]} -gt 0 && ${child_stack[-1]} -eq 0 ]]; do
				unset 'child_stack[-1]'
			done
		}

		# Extract the window title from the line
		extract_title() {
			local line="$1"
			
			# Extract window name or return "(has no name)" if no name is found
			if [[ "$line" =~ ^0x[0-9a-fA-F]+\ (.*): ]]; then
				local title="${BASH_REMATCH[1]}"
				if [[ "$title" =~ \"(.*)\" ]]; then
					printf "%s" "${BASH_REMATCH[1]}"  # Extract the window name inside quotes
				else
					printf "(has no name)"
				fi
			fi
		}

		# Process the output of xwininfo -root -tree
		DISPLAY=":$display_id" xwininfo -root -tree | while read -r line; do
			# Check if the line contains a number of children (increasing depth)
			if [[ "$line" =~ ([0-9]+)\ children ]]; then
				append_with_indent ${#child_stack[@]} "$(extract_title "$line") - ${BASH_REMATCH[1]} children"
				child_stack+=("${BASH_REMATCH[1]}")  # Push number of children to the stack
			# Check if the line indicates a single child
			elif [[ "$line" =~ ([0-9]+)\ child ]]; then
				append_with_indent ${#child_stack[@]} "$(extract_title "$line") - 1 child"
				child_stack+=(1)  # Push 1 child to the stack
			# Detect window entries with a hex code followed by a colon (extract window title)
			elif [[ "$line" =~ ^0x[0-9a-fA-F]+ ]]; then
				append_with_indent ${#child_stack[@]} "$(extract_title "$line")"
				
				# Decrement the child count at the current depth
				if [[ ${#child_stack[@]} -gt 0 ]]; then
					child_stack[-1]=$((child_stack[-1] - 1))
					pop_stack
				fi
			fi
		done

		echo "$output"
	}

    # Parse the command and arguments
    case "$1" in
        start)
            start_xvfb "$2"
            ;;
        stop)
            stop_xvfb "$2"
            ;;
        list)
            list_xvfb
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Invalid command or option."
            usage
            ;;
    esac
}
