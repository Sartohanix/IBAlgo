#!/bin/bash

uninstall_ibgateway() {
    if [ "$preserve" = "true" ]; then
        save_from_uninstall ("ibgateway_installer.sh" "Jts/")
    fi
}