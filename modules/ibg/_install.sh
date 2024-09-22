#!/bin/bash

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
    if [ -f "$installer_file" ]; then
        echo "IBGateway installer already exists. Skipping download."
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

    expect <<EOF > "$log_file" 2>&1
        set timeout -1
        log_user 1
        spawn sh "$installer_file" -c
        expect {
            "Where should * be installed?" {
                send "$l_dir\r"
            }
        }
        expect {
            -r "The directory:.*already exists.*" {
                send "\r"
            }
        }
        expect {
            -r "Run *" {
                send "\r"
            }
        }
        expect eof
EOF

    # Check if installation was successful
    if [ -d "$install_dir" ]; then
        echo "IBGateway installation completed successfully."

        # # Update config.json with new version and path
        # major_version=$(echo "$IBG_VERSION" | sed -E 's/([0-9]+)\.([0-9]+)\..*/\1\2/')
        # jq ".ibgateway.version = \"$IBG_VERSION\" | .ibgateway.path = \"$l_dir\" | .ibgateway.major_version = \"$major_version\"" "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
        
        # Copy the log file to the installation directory
        cp "$log_file" "$l_dir"
    else
        echo "IBGateway installation failed."
        return 1
    fi
}

install_ibgateway