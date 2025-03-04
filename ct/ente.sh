#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Jstaud
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://ente.cc/

APP="ente.cc"
var_tags="cloud;storage"
var_cpu="2"
var_ram="2048"
var_disk="10"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    msg_info "Updating ${APP} LXC"
    $STD apt-get update
    $STD apt-get -y upgrade

    msg_info "Installing Docker"
    $STD apt-get install -y docker.io
    msg_ok "Docker installed successfully"

    msg_info "Cloning ${APP} repository"
    git clone https://github.com/ente-io/ente /opt/ente
    cd /opt/ente/server
    msg_ok "Repository cloned successfully"

    msg_info "Starting ${APP} server with Docker Compose"
    $STD docker compose up --build -d
    msg_ok "${APP} server started successfully"

    msg_info "Installing npm and yarn"
    $STD apt-get install -y nodejs npm
    $STD npm install -g yarn
    msg_ok "npm and yarn installed successfully"

    msg_info "Setting up ${APP} web client"
    cd /opt/ente/web
    git submodule update --init --recursive
    $STD yarn install
    NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 $STD yarn build
    msg_ok "${APP} web client set up successfully"

    if [[ ! -d /opt/ente ]]; then
      msg_error "No ${APP} Installation Found!"
      exit
    fi
    msg_ok "Updated Successfully"
    exit
}

start
build_container
description

# Fetch the IP address of the container
IP=$(pct exec $CTID -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"