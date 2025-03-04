#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Jstaud
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://ente.cc/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y git curl sudo mc docker.io nodejs npm
msg_ok "Installed Dependencies"

msg_info "Cloning ente.cc repository"
$STD git clone https://github.com/ente-io/ente /opt/ente
msg_ok "Repository cloned successfully"

msg_info "Starting ente.cc server with Docker Compose"
$STD docker compose -f /opt/ente/server/docker-compose.yml up --build -d
msg_ok "ente.cc server started successfully"

msg_info "Installing yarn"
$STD npm install -g yarn
msg_ok "npm and yarn installed successfully"

msg_info "Setting up ente.cc web client"
$STD bash -c "cd /opt/ente/web && git submodule update --init --recursive && yarn install && NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 yarn build"
msg_ok "ente.cc web client set up successfully"

