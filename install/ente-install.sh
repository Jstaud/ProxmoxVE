#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Jstaud
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://ente.cc/

# Import Functions and Setup
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Ensure CTID is set
if [[ -z "$CTID" ]]; then
  msg_error "Container ID (CTID) is not set!"
  exit 1
fi

# Installing Dependencies inside the LXC Container
msg_info "Installing Dependencies inside LXC Container"
pct exec $CTID -- apt-get update
pct exec $CTID -- apt-get install -y \
  curl \
  sudo \
  mc \
  git \
  docker.io \
  docker-compose \
  nodejs \
  npm
msg_ok "Installed Dependencies inside LXC"

# Fetch latest release
msg_info "Fetching latest release of Ente"
REPO="ente-io/ente"
RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
msg_ok "Latest release: v${RELEASE}"

# Clone repository inside the container
msg_info "Cloning Ente repository inside LXC"
pct exec $CTID -- bash -c "[ ! -d /opt/ente ] && git clone https://github.com/$REPO.git /opt/ente || (cd /opt/ente && git pull)"
msg_ok "Repository cloned successfully"

# Start Ente server with Docker Compose inside the container
msg_info "Starting Ente server inside LXC"
pct exec $CTID -- bash -c "cd /opt/ente/server && docker-compose up --build -d"
msg_ok "Ente server started successfully"

# Installing Yarn for frontend inside the container
msg_info "Installing Yarn inside LXC"
pct exec $CTID -- npm install -g yarn
msg_ok "Yarn installed successfully"

# Setting up Ente Web Client inside the container
msg_info "Setting up Ente Web Client inside LXC"
pct exec $CTID -- bash -c "cd /opt/ente/web && git submodule update --init --recursive && yarn install && NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 yarn build"
msg_ok "Web Client setup completed"

# Save version inside the container
pct exec $CTID -- bash -c "echo '${RELEASE}' > /opt/ente_version.txt"

# Cleanup inside LXC
msg_info "Cleaning up inside LXC"
pct exec $CTID -- bash -c "apt-get -y autoremove && apt-get -y autoclean"
msg_ok "Cleanup completed inside LXC"

# Fetch the IP address of the container
IP=$(pct exec $CTID -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Display the final message to the user
msg_ok "Installation Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
