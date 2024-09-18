#!/bin/bash
# This install script should be sourced from within a terminal.


# =======================================
#           Dependency check
# =======================================

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to use this script."
    return 0
fi

# =======================================
#    Global variables: initialisation
# =======================================

ibalgo_content=""
install_dir=""

config_url="https://raw.githubusercontent.com/Sartohanix/IBAlgo/master/config.json"
config_file=""



# =======================================
#    Auxiliary functions: definition
# =======================================


check_existing_installation() {
    local bashrc_file="$HOME/.bashrc"
    local ibalgo_header="# BEGIN IBALGO FRAMEWORK FUNCTIONS"
    local ibalgo_footer="# END IBALGO FRAMEWORK FUNCTIONS"

    if grep -q "$ibalgo_header" "$bashrc_file" && grep -q "$ibalgo_footer" "$bashrc_file"; then
        # Extract the IBALGO_PATH from .bashrc
        install_dir=$(sed -n "/$ibalgo_header/,/$ibalgo_footer/p" "$bashrc_file" | grep 'export IBALGO_PATH=' | cut -d'"' -f2)

        if [ -n "$install_dir" ]; then
            echo "Existing IBAlgo installation detected at: $install_dir"
        else
            echo "Existing IBAlgo installation detected, but couldn't determine the installation path."
            return 1
        fi

        echo
        echo "Please choose an option:"
        echo
        options=("[ ] Repair/Update the IBAlgo install" "[ ] Abort installation" "[ ] Fully reinstall (delete settings and modules)")
        selected=0

        print_menu() {
            for i in "${!options[@]}"; do
                if [ $i -eq $selected ]; then
                    echo -e "\e[1m\e[32m${options[$i]/\[ \]/[x]}\e[0m"
                else
                    echo "${options[$i]}"
                fi
            done
        }

        print_menu

        while true; do
            read -s -n 1 key
            case "$key" in
                A) # Up arrow
                    ((selected--))
                    if [ $selected -lt 0 ]; then
                        selected=$((${#options[@]} - 1))
                    fi
                    ;;
                B) # Down arrow
                    ((selected++))
                    if [ $selected -ge ${#options[@]} ]; then
                        selected=0
                    fi
                    ;;
                '') # Enter key
                    break
                    ;;
            esac
            tput cuu ${#options[@]}
            print_menu
        done

        case $selected in
            0)
                echo -e "\nProceeding with repair/update..."
                return 0
                ;;
            1)
                echo -e "\nInstallation aborted."
                return 1
                ;;
            2)
                echo -e "\nProceeding with full reinstallation..."

                #TODO : UNINSTALL EXISTING INSTALL

                install_dir=""  # Clear install_dir to prompt for a new location
                return 0
                ;;
        esac
    else
        install_dir=""  # No existing installation found
    fi
}

generate_command_script() {
    local command_name="$1"
    
    # Extract command information
    local json_content=$(cat "$config_file")
    local description=$(echo "$json_content" | jq -r ".commands.$command_name.description")
    
    # Get subcommands and their priorities
    local subcommands_with_priority=$(echo "$json_content" | jq -r ".commands.$command_name.subcommands | to_entries[] | \"\(.key):\(.value.pp // 0)\"")
    
    # Sort subcommands based on priority
    local sorted_subcommands=$(echo "$subcommands_with_priority" | sort -t':' -k2 -nr | cut -d':' -f1 | tac)
    
    # Find the longest subcommand name for alignment
    local max_length=0
    for subcommand in $sorted_subcommands; do
        local length=${#subcommand}
        if (( length > max_length )); then
            max_length=$length
        fi
    done
    
    # Generate the script content
    echo "#!/bin/bash"
    echo
    echo "usage() {"
    echo "    echo \"Description: $description\""
    echo "    echo \"\""
    echo "    echo \"Usage: $command_name <subcommand> [options] [arguments]\""
    echo "    echo \"\""
    echo "    echo \"Available subcommands:\""

    # Generate subcommand descriptions with aligned colons
    for subcommand in $sorted_subcommands; do
        local subcommand_description=$(echo "$json_content" | jq -r ".commands.$command_name.subcommands.$subcommand.description")
        printf "    echo \"    %-*s : %s\"\n" "$max_length" "$subcommand" "$subcommand_description"
    done

    echo
    echo "    echo \"\""
    echo "    echo \"For more information on a specific subcommand, use: $command_name <subcommand> help\""
    echo "}"
    echo
    echo "if [ \$# -eq 0 ] || [ \"\$1\" = \"help\" ]; then"
    echo "    usage"
    echo "    exit 0"
    echo "fi"
    echo
    echo "subcommand=\"\$1\""
    echo "shift"
    echo
    echo "case \"\$subcommand\" in"

    # Generate case statements for each subcommand
    for subcommand in $sorted_subcommands; do
        local nargs=$(echo "$json_content" | jq -r ".commands.$command_name.subcommands.$subcommand.nargs // 0")
        local options=$(echo "$json_content" | jq -r ".commands.$command_name.subcommands.$subcommand.options | keys[]" 2>/dev/null)
        
        echo "    $subcommand)"
        echo "        ${subcommand}_usage() {"
        echo "            echo \"Usage: $command_name $subcommand [options] <arguments>\""
        echo "            echo \"Description: $(echo "$json_content" | jq -r ".commands.$command_name.subcommands.$subcommand.description")\""
        if [ -n "$options" ]; then
            echo "            echo \"Options:\""
            for option in $options; do
                local option_description=$(echo "$json_content" | jq -r ".commands.$command_name.subcommands.$subcommand.options.\"$option\".description")
                if [[ $option =~ ^--[^|]+\|-[a-zA-Z]$ ]]; then
                    echo "            echo \"    $option: $option_description\""
                elif [[ $option =~ ^--[^|]+$ ]]; then
                    echo "            echo \"    $option: $option_description\""
                else
                    echo "            echo \"Error: Invalid option format for '$option'\""
                fi
            done
        fi
        echo "        }"
        echo
        echo "        if [ \"\$1\" = \"help\" ] && [ \$# -eq 1 ]; then"
        echo "            ${subcommand}_usage"
        echo "            exit 0"
        echo "        fi"
        echo
        echo "        # Parse options"
        if [ -n "$options" ]; then
            echo "        while [[ \$# -gt 0 && \$1 == -* ]]; do"
            echo "            case \"\$1\" in"
            for option in $options; do
                if [[ $option =~ ^--([^|]+)\|-([a-zA-Z])$ ]]; then
                    local full_opt="${BASH_REMATCH[1]}"
                    local short_opt="${BASH_REMATCH[2]}"
                    echo "                --$full_opt|-$short_opt)"
                    echo "                    # Handle option --$full_opt|-$short_opt"
                    echo "                    shift"
                    echo "                    ;;"
                elif [[ $option =~ ^--([^|]+)$ ]]; then
                    local full_opt="${BASH_REMATCH[1]}"
                    echo "                --$full_opt)"
                    echo "                    # Handle option --$full_opt"
                    echo "                    shift"
                    echo "                    ;;"
                else
                    echo "                # Error: Invalid option format for '$option'"
                fi
            done
            echo "                *)"
            echo "                    echo \"Error: Unknown option \$1 for $subcommand\""
            echo "                    ${subcommand}_usage"
            echo "                    exit 1"
            echo "                    ;;"
            echo "            esac"
            echo "        done"
        else
            echo "        if [[ \$1 == -* ]]; then"
            echo "            echo \"Error: $subcommand does not accept any options\""
            echo "            ${subcommand}_usage"
            echo "            exit 1"
            echo "        fi"
        fi
        echo
        echo "        if [ \$# -ne $nargs ]; then"
        echo "            echo \"Error: $subcommand requires $nargs argument(s).\""
        echo "            ${subcommand}_usage"
        echo "            exit 1"
        echo "        fi"
        echo
        echo "        # Add your implementation for the $subcommand subcommand here"
        echo "        echo \"Executing $subcommand subcommand\""
        echo "        ;;"
    done

    # Close the case statement and the script
    echo "    *)"
    echo "        echo \"Error: Unknown subcommand '\$subcommand'\""
    echo "        usage"
    echo "        exit 1"
    echo "        ;;"
    echo "esac"
}

generate_all_command_scripts() {
    # Get the list of commands from the config file
    commands=$(jq -r '.commands | keys[]' "$config_file")

    if [ -z "$commands" ]; then
        echo "Error: No commands found in the config file."
        return 1
    fi

    # Generate scripts for each command
    for cmd in $commands; do
        output_file="$install_dir/$cmd"
        echo " - Generating script for command: $cmd"
        generate_command_script "$cmd" > "$output_file"
        if [ $? -eq 0 ]; then
            chmod +x "$output_file"
            echo "  -> Successfully generated the executable '$output_file'"
        else
            echo "Error generating script for $cmd"
        fi
        echo
    done
}

update_bashrc() {
    local bashrc_file="$HOME/.bashrc"
    local ibalgo_header="# BEGIN IBALGO FRAMEWORK FUNCTIONS"
    local ibalgo_footer="# END IBALGO FRAMEWORK FUNCTIONS"
    ibalgo_content=""

    # Generate function definitions
    ibalgo_content+="export IBALGO_PATH=\"$install_dir\"\n\n"
    for cmd in $commands; do
        ibalgo_content+="$cmd() {\n"
        ibalgo_content+="    \"\$IBALGO_PATH/$cmd\" \"\$@\"\n"
        ibalgo_content+="}\n\n"
    done

    # Check if IBAlgo section already exists in .bashrc
    if grep -q "$ibalgo_header" "$bashrc_file"; then
        # Update existing section
        sed -i "/$ibalgo_header/,/$ibalgo_footer/c\\
$ibalgo_header\\
$ibalgo_content\\
$ibalgo_footer" "$bashrc_file"
    else
        # Append new section
        echo -e "\n$ibalgo_header\n$ibalgo_content$ibalgo_footer" >> "$bashrc_file"
    fi
}


# =======================================
#        Main script: execution
# =======================================


echo
echo "======================================="
echo "   Welcome to the IBAlgo Framework"
echo "======================================="
echo

# Call the function to check for existing installation
check_existing_installation

if [ $? -eq 1 ]; then
    return 1
fi

# Only prompt for installation directory if it's not set (new install or full reinstall)
if [ -z "$install_dir" ]; then
    read -p "Enter the installation directory for IBAlgo (default: ~/IBAlgo): " user_input
    install_dir=${user_input:-~/IBAlgo}
    install_dir=$(eval echo $install_dir)  # Expand ~ if present
fi

# Create the installation directory if it doesn't exist
mkdir -p "$install_dir"

# Define the config file path and download it from the GitHub repository
config_file="$install_dir/config.json"

# Download the config file
echo "Downloading config file from $config_url..."
if ! curl -o "$config_file" "$config_url"; then
    echo "Error: Failed to download config file from $config_url. Aborting installation."
    return 1
fi

# Check if config file exists
if [ ! -f "$config_file" ]; then
    echo "Error: Config file not found at $config_file. Aborting installation."
    return 1
fi

echo "DEBUG: Config file content:"
cat "$config_file"


generate_all_command_scripts
update_bashrc


if [ -n "$ibalgo_content" ]; then
    echo "$ibalgo_content" | eval
fi

# Copy config.json and IBAlgo.sh to install_dir
current_dir=$(dirname "${BASH_SOURCE[0]}")
cp "$current_dir/config.json" "$install_dir/"
cp "$current_dir/IBAlgo.sh" "$install_dir/"

# Copy _iba directory and its subdirectories if they don't exist
iba_dir="$current_dir/_iba"
if [ -d "$iba_dir" ]; then
    # Copy _iba directory if it doesn't exist in install_dir
    if [ ! -d "$install_dir/_iba" ]; then
        cp -r "$iba_dir" "$install_dir/"
    fi

    # Copy each subdirectory of _iba if it doesn't exist in install_dir
    for subdir in "$iba_dir"/*; do
        if [ -d "$subdir" ]; then
            subdir_name=$(basename "$subdir")
            if [ ! -d "$install_dir/_iba/$subdir_name" ]; then
                cp -r "$subdir" "$install_dir/_iba/"
            fi
        fi
    done
fi

unset ibalgo_content
unset install_dir
unset config_file

echo
echo "Setup process completed successfully."
echo "======================================="
