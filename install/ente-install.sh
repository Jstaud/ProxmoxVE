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
msg_info "Installing Dependencies (Parallel Downloading Enabled) NOTE: This will take a while, grab some coffee"
export DEBIAN_FRONTEND=noninteractive
$STD apt-get update -q
$STD apt-get install -y --no-install-recommends --no-upgrade \
  curl sudo mc git nodejs npm
msg_ok "Installed Dependencies"

get_latest_release() {
  curl -sL https://api.github.com/repos/$1/releases/latest | grep '"tag_name":' | cut -d'"' -f4
}

DOCKER_LATEST_VERSION=$(get_latest_release "moby/moby")
DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")

msg_info "Installing Docker $DOCKER_LATEST_VERSION"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -sSL https://get.docker.com)
msg_ok "Installed Docker $DOCKER_LATEST_VERSION"

msg_info "Installing Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"
$STD curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_LATEST_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
msg_ok "Installed Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"

# Ensure user is added to the docker group
msg_info "Adding $(whoami) to docker group"
usermod -aG docker $(whoami)
msg_ok "User added to docker group"

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
    msg_info "Repository already exists, checking for updates"
    cd /opt/ente || exit
    $STD git fetch origin
    $STD git reset --hard origin/main
fi
msg_ok "Repository cloned and updated successfully"

# Start Ente server with Docker Compose
msg_info "Starting Ente server using prebuilt Docker image"
cd /opt/ente/server || exit
sed -i 's|build:|# build:|g' compose.yaml
sed -i 's|context: .|# context: .|g' compose.yaml
sed -i 's|args:|# args:|g' compose.yaml
sed -i 's|GIT_COMMIT: development-cluster|# GIT_COMMIT: development-cluster|g' compose.yaml
sed -i 's|# image: ghcr.io/ente-io/server|image: ghcr.io/ente-io/server|g' compose.yaml
touch museum.yaml
$STD docker-compose up -d
msg_ok "Ente server started using prebuilt image"


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
ExecStart=/usr/bin/docker-compose -f /opt/ente/server/docker-compose.yml up --build -d
Restart=always
User=root
WorkingDirectory=/opt/ente

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now ente.service
msg_ok "Ente Service created and started"

# Setup Message of the Day and Customizations
motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleanup completed successfully"
