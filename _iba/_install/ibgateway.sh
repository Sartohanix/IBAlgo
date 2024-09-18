#!/bin/bash

install_ibgateway() {
    local force_reinstall=$1
    local install_dir="$IBA_PATH/ibg"
    local tmp_dir="$IBA_PATH/.ibg"

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

    # Step 2: Get information from config.json
    local config_file="$IBA_PATH/config.json"
    if [ ! -f "$config_file" ]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    local current_version=$(jq -r '.ibgateway.version' "$config_file" 2>/dev/null)
    local current_path=$(jq -r '.ibgateway.path' "$config_file" 2>/dev/null)

    if [ -n "$current_version" ] || [ -n "$current_path" ]; then
        if [ -n "$current_version" ] && [ -n "$current_path" ]; then
            # Step 2a: Check if version is up to date
            if [ "$current_version" = "$IBG_VERSION" ] && [ "$force_reinstall" != "true" ]; then
                echo "IBGateway is already up to date (version $current_version)."
                return 0
            fi

            # Step 2b: Check if an update is available
            if [ "$current_version" != "$IBG_VERSION" ]; then
                echo "A new version of IBGateway is available (current: $current_version, new: $IBG_VERSION)."
                read -p "Do you want to proceed with the update? (y/n) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Update cancelled."
                    return 0
                fi
            fi
        else
            echo "Installation appears to be broken. Proceeding with reinstallation."
        fi
    fi

    # Remove existing install_dir if it exists
    if [ -d "$install_dir" ]; then
        echo "Removing existing installation directory..."
        rm -rf "$install_dir"
    fi

    # Create tmp_dir and download the installer
    mkdir -p "$tmp_dir"
    local installer_file="$tmp_dir/ibgateway_installer.sh"
    echo "Downloading IBGateway installer... (Size: $IBG_FILE_SIZE)"
    
    curl -# -o "$installer_file" "$IBG_DOWNLOAD_URL"

    if [ $? -ne 0 ]; then
        echo "Failed to download IBGateway installer."
        rm -rf "$tmp_dir"
        return 1
    fi

    local log_file="$tmp_dir/ibgateway_auto_install.log"
    touch "$log_file"

    echo "Running IBGateway installer... This may take up to a few minutes."

    expect <<EOF > "$log_file" 2>&1
    set timeout -1
    log_user 1
    spawn sh "$installer_file" -c
    expect {
        "Where should * be installed?" {
            send "$install_dir\r"
        }
    }
    expect {
        "Run *?" {
            send "n\r"
        }
    }
    expect eof
EOF

    # Check if installation was successful
    if [ -d "$install_dir" ]; then
        echo "IBGateway installation completed successfully."
        # Update config.json with new version and path
        major_version=$(echo "$IBG_VERSION" | sed -E 's/([0-9]+)\.([0-9]+)\..*/\1\2/')
        jq ".ibgateway.version = \"$IBG_VERSION\" | .ibgateway.path = \"$install_dir\" | .ibgateway.major_version = \"$major_version\"" "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
        
        
        # Copy the log file to the installation directory
        cp "$log_file" "$install_dir"

        # Remove the temporary directory
        rm -rf "$tmp_dir"
    else
        echo "IBGateway installation failed."
        return 1
    fi
}
