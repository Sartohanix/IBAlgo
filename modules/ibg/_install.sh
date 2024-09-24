#!/bin/bash

check_install() {
    local jars_dir="$l_dir/jars"
    local log_file="$l_dir/ibgateway_auto_install.log"
    local install_complete_msg="Setup has finished installing IB Gateway"

    if [ ! -d "$jars_dir" ]; then
        echo "Error: 'jars' folder not found in $l_dir"
        return 1
    fi

    if [ ! -f "$log_file" ]; then
        echo "Error: Installation log file not found at $log_file"
        return 1
    fi

    if ! grep -q "$install_complete_msg" "$log_file"; then
        echo "Error: Installation completion message not found in log file"
        return 1
    fi

    echo "Installation check passed successfully"
    return 0
}

install_ibgateway() {
    # Step 1: Get information from get_ibg_installer_info
    local URL="https://www.interactivebrokers.com/en/trading/ibgateway-stable.php"
    local version_json_url="https://download2.interactivebrokers.com/installers/ibgateway/stable-standalone/version.json"
    
    local html_content=$(curl -s "$URL")

    if [[ -z "$html_content" ]]; then
        echo "Error: Failed to download or retrieve the webpage content."
        return 1
    fi

    local linux_section=$(echo "$html_content" | grep -ozP '(?s)<section id="tws-software-linux64-sw"[^>]*>.*?</section>' | tr -d '\0')
    local version=$(curl -s "$version_json_url" | grep -oP '(?<="buildVersion":")[^"]+')
    local download_url=$(echo "$linux_section" | grep -oP 'href="\Khttps://[^"]+ibgateway-stable-standalone-linux-x64\.sh' | head -1)
    local file_size=$(echo "$linux_section" | grep -oP 'File Size: \K[0-9.]+ ?(MB|GB)' | head -1)

    IBG_VERSION="$version"
    IBG_DOWNLOAD_URL="$download_url"
    IBG_FILE_SIZE="$file_size"

    # Step 2: Download the installer
    local installer_file="$tmp_dir/ibgateway_installer.sh"

    if [ -f "$l_dir/ibgateway_installer.sh" ]; then
        echo "IBGateway installer already exists. Skipping download."
        mv $l_dir/ibgateway_installer.sh $tmp_dir/ibgateway_installer.sh

        # Cleaning old install&log files
        rm -f "$l_dir/*.log"
        if [ -d "$l_dir/ibgateway_installer.sh.*" ]; then
            rm -r "$l_dir/ibgateway_installer.sh.*"
        fi
    else
        echo "Downloading IBGateway installer... (Size: $IBG_FILE_SIZE)"
        
        curl -# -o "$installer_file" "$IBG_DOWNLOAD_URL"

        if [ $? -ne 0 ]; then
            echo "Failed to download IBGateway installer."
            return 1
        fi
    fi

    local log_file="$tmp_dir/ibgateway_auto_install.log"
    touch "$log_file"

    # Step 3: Run the installer
    echo "Running IBGateway installer... This may take up to a few minutes."

    expect <<EOF > "$log_file" #2>&1
        set timeout -1
        set log_user 1
        spawn sh "$installer_file" -c
        expect {
            "Where should * be installed?" {
                send "$l_dir\r"
                send_user "DEBUG: Sending installation directory $l_dir\n"
            }
        }
        expect {
            "The directory:*already exists*" {
                send "\r"
                send_user "DEBUG: Sending ENTER key (existing dir)\n"
                exp_continue
            }
            "*Run IB Gateway*" {
                send "\r"
                send_user "DEBUG: Sending ENTER key (running ibg)\n"
            }
        }
EOF

    # Copy the installation log file to the module's main directory
    cp "$log_file" "$l_dir"

    # Checks proper installation
    if ! check_install; then
        echo "Error: IBGateway installation failed."
        return 1
    fi

    # Store the installation file in the module's main directory
    mv "$installer_file" "$l_dir"

    return 0
}

install_ibgateway