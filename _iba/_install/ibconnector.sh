#!/bin/bash

get_ibc_info() {
    local version_url="https://raw.githubusercontent.com/Sartohanix/IBC/master/version"
    local download_url="https://api.github.com/repos/Sartohanix/IBC/tarball/master"
    
    # Fetch the version
    IBC_VERSION=$(curl -s "$version_url")
    
    if [[ -z "$IBC_VERSION" ]]; then
        echo "Error: Failed to retrieve IBC version."
        return 1
    fi

    IBC_DOWNLOAD_URL="$download_url"

    #DEBUG
    echo "IBC Version: $IBC_VERSION"
    echo "IBC Download URL: $IBC_DOWNLOAD_URL"

    return 0
}

install_ibconnector() {
    local force_reinstall=$1
    local install_dir="$IBA_PATH/ibc"
    local tmp_dir="$IBA_PATH/.ibc"

    # Step 1: Get information from get_ibc_info
    get_ibc_info
    if [ $? -ne 0 ]; then
        echo "Failed to retrieve IBConnector information."
        return 1
    fi

    # Step 2: Get information from config.json
    local config_file="$IBA_PATH/config.json"
    if [ ! -f "$config_file" ]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    local current_version=$(jq -r '.ibconnector.version' "$config_file" 2>/dev/null)
    local current_path=$(jq -r '.ibconnector.path' "$config_file" 2>/dev/null)

    if [ -n "$current_version" ] || [ -n "$current_path" ]; then
        if [ -n "$current_version" ] && [ -n "$current_path" ]; then
            # Step 2a: Check if version is up to date
            if [ "$current_version" = "$IBC_VERSION" ] && [ "$force_reinstall" != "true" ]; then
                echo "IBConnector is already up to date (version $current_version)."
                return 0
            fi

            # Step 2b: Check if an update is available
            if [ "$current_version" != "$IBC_VERSION" ]; then
                echo "A new version of IBConnector is available (current: $current_version, new: $IBC_VERSION)."
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

    # Install process for IBC
    echo "Downloading IBConnector..."
    mkdir -p "$tmp_dir"
    curl -L "$IBC_DOWNLOAD_URL" -o "$tmp_dir/ibc.tar.gz"
    
    echo "Extracting IBConnector..."
    mkdir -p "$install_dir"
    tar -xzf "$tmp_dir/ibc.tar.gz" -C "$install_dir" --strip-components=1
    
    if [ $? -ne 0 ]; then
        echo "Failed to extract IBConnector."
        rm -rf "$tmp_dir"
        return 1
    fi

    # Check if installation was successful
    if [ -d "$install_dir" ]; then
        echo "IBConnector installation completed successfully."
        # Update config.json with new version and path
        jq ".ibconnector.version = \"$IBC_VERSION\" | .ibconnector.path = \"$install_dir\"" "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
        
        # Remove the temporary directory
        rm -rf "$tmp_dir"
    else
        echo "IBConnector installation failed."
        return 1
    fi
}