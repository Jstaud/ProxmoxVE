#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Jstaud
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://ente.cc/

# Import functions from build.func
source <(curl -s https://raw.githubusercontent.com/Jstaud/ProxmoxVE/refs/heads/ente-docker-lxc-script/misc/build.func)

# Default Values
APP="Ente"
var_tags="cloud;storage"
var_cpu="2"
var_ram="2048"
var_disk="10"
var_os="debian"
var_version="12"
var_unprivileged="1"
var_verbose="0"

# Generate header for the application
header_info "$APP"

# Initialize variables, color codes, and error handling
variables
color
catch_errors

# Function to update the application
# Function to update the Ente.cc application
function update_script() {
    header_info
    check_container_storage
    check_container_resources

    # Check if Ente.cc is installed
    if [[ ! -d /opt/ente ]]; then
        msg_error "No Ente.cc installation found!"
        exit 1
    fi

    # Fetch latest release from Ente.cc GitHub repo
    msg_info "Checking for the latest Ente.cc release"
    REPO="ente-io/ente"
    RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')

    # Check if update is needed
    if [[ ! -f /opt/ente_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/ente_version.txt)" ]]; then
        msg_info "Updating Ente.cc to v${RELEASE}"

        # Backup current data
        msg_info "Backing up current Ente.cc data"
        mv /opt/ente /opt/ente-backup

        # Pull latest changes from GitHub
        msg_info "Pulling latest changes from repository"
        git clone https://github.com/$REPO.git /opt/ente
        msg_ok "Repository updated successfully"

        # Start Ente server with Docker Compose
        msg_info "Rebuilding and restarting Ente.cc server"
        cd /opt/ente/server
        docker-compose down
        docker-compose up --build -d
        msg_ok "Ente.cc server restarted successfully"

        # Updating Ente web client
        msg_info "Updating Ente.cc Web Client"
        cd /opt/ente/web
        git submodule update --init --recursive
        yarn install
        NEXT_PUBLIC_ENTE_ENDPOINT="http://localhost:8080" yarn build
        msg_ok "Web client updated successfully"

        # Restore data from backup if necessary
        msg_info "Restoring user data"
        cp /opt/ente-backup/.env /opt/ente/.env
        cp -r /opt/ente-backup/public/uploads/ /opt/ente/public/uploads/
        cp -r /opt/ente-backup/storage/private_uploads /opt/ente/storage/private_uploads/

        # Save the new version
        echo "${RELEASE}" > "/opt/ente_version.txt"

        # Cleanup old data
        msg_info "Cleaning up"
        rm -rf /opt/ente-backup
        docker system prune -af
        msg_ok "Update completed successfully"
    else
        msg_ok "No update required. Ente.cc is already at v${RELEASE}."
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
