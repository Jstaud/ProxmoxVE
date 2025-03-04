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

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  git \
  docker.io \
  nodejs \
  npm
msg_ok "Installed Dependencies"

# Fetch latest release
msg_info "Fetching latest release of Ente"
REPO="ente-io/ente"
RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
msg_ok "Latest release: v${RELEASE}"

# Clone repository and set up
msg_info "Cloning Ente repository"
if [ ! -d "/opt/ente" ]; then
    $STD git clone https://github.com/$REPO.git /opt/ente
else
    msg_info "Repository already exists, pulling latest changes"
    $STD git -C /opt/ente pull
fi
msg_ok "Repository cloned successfully"

# Start Ente server with Docker Compose
msg_info "Starting Ente server with Docker Compose"
$STD docker compose -f /opt/ente/server/docker-compose.yml up --build -d
msg_ok "Ente server started successfully"

# Installing Yarn for frontend
msg_info "Installing Yarn"
$STD npm install -g yarn
msg_ok "Yarn installed successfully"

# Setting up Ente Web Client
msg_info "Setting up Ente Web Client"
(
    cd /opt/ente/web || exit
    $STD git submodule update --init --recursive
    $STD yarn install
    NEXT_PUBLIC_ENTE_ENDPOINT="http://localhost:8080" $STD yarn build
)
msg_ok "Web Client setup completed"

# Save version
echo "${RELEASE}" > /opt/ente_version.txt

# Creating Systemd Service
msg_info "Creating Ente Service"
cat <<EOF >/etc/systemd/system/ente.service
[Unit]
Description=Ente Storage Service
After=network.target

[Service]
ExecStart=/usr/bin/docker compose -f /opt/ente/server/docker-compose.yml up --build -d
Restart=always
User=root
WorkingDirectory=/opt/ente

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now ente.service
msg_ok "Ente Service created and started"

# Setup Message of the Day and Customizations
motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
rm -f ${RELEASE}.zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleanup completed successfully"
