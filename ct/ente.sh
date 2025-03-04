#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Jstaud
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://ente.cc/

# Import functions from build.func
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Default Values
APP="ente.cc"
var_tags="cloud;storage"
var_cpu="2"
var_ram="2048"
var_disk="10"
var_os="debian"
var_version="12"
var_unprivileged="1"

# Generate header for the application
header_info "$APP"

# Initialize variables, color codes, and error handling
variables
color
catch_errors

# Function to update the application
function update_script() {
    header_info
    check_container_storage
    check_container_resources

    # Check if the application is installed
    if [[ ! -d /opt/$APP ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    # Check the current installed version
    local RELEASE=$(curl -fsSL https://api.github.com/repos/snipe/snipe-it/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
    if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
        msg_info "Updating ${APP} to v${RELEASE}"

        # Backup current data
        msg_info "Backing up current ${APP} data"
        mv /opt/${APP} /opt/${APP}-backup

        # Pull latest changes
        pct exec $CTID -- bash -c "cd /opt/$APP && git pull"
        msg_ok "Repository updated successfully"

        # Rebuild the application
        msg_info "Rebuilding ${APP} server with Docker Compose"
        pct exec $CTID -- docker compose -f /opt/$APP/server/docker-compose.yml up --build -d
        msg_ok "${APP} server rebuilt successfully"

        # Update the web client
        msg_info "Updating ${APP} web client"
        pct exec $CTID -- bash -c "cd /opt/$APP/web && git submodule update --init --recursive && yarn install && NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 yarn build"
        msg_ok "${APP} web client updated successfully"

        # Restore data from backup if necessary
        msg_info "Restoring user data"
        cp /opt/${APP}-backup/.env /opt/$APP/.env
        cp -r /opt/${APP}-backup/public/uploads/ /opt/$APP/public/uploads/
        cp -r /opt/${APP}-backup/storage/private_uploads /opt/$APP/storage/private_uploads/

        # Update the version file
        echo "${RELEASE}" >"/opt/${APP}_version.txt"

        # Cleanup temporary files
        msg_info "Cleaning up"
        rm -rf /opt/${APP}-backup
        rm -rf /opt/v${RELEASE}.zip
        $STD apt-get -y autoremove
        $STD apt-get -y autoclean
        msg_ok "Update completed successfully"
    else
        msg_ok "No update required. ${APP} is already at v${RELEASE}."
    fi
}

# Start the installation process
start
build_container
description

# Fetch the IP address of the container for user access
IP=$(pct exec $CTID -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Display the final message to the user
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
