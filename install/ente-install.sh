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

# ⚡ Prompt the user for PostgreSQL credentials
echo -e "\n🔹 Enter PostgreSQL Database Details:"
read -p "📌 Database Host (e.g., db.example.com): " DB_HOST
read -p "📌 Database Port (default 5432): " DB_PORT
DB_PORT=${DB_PORT:-5432}  # Use default 5432 if empty
read -p "📌 Database Name: " DB_NAME
read -p "📌 Database Username: " DB_USER
read -s -p "🔑 Database Password: " DB_PASS
echo ""  # Newline after password input

# ⚡ Prompt the user for MinIO (S3) credentials
echo -e "\n🔹 Enter MinIO (S3) Storage Details:"
read -p "📌 MinIO Host (e.g., s3.example.com): " S3_HOST
read -p "📌 MinIO Port (default 3200): " S3_PORT
S3_PORT=${S3_PORT:-3200}  # Default port
read -p "📌 MinIO Access Key: " S3_ACCESS_KEY
read -s -p "🔑 MinIO Secret Key: " S3_SECRET_KEY
echo ""  # Newline after password input
read -p "📌 MinIO Bucket Name: " S3_BUCKET

# 📝 Create the `credentials.yaml` file
cat <<EOF > /opt/ente/server/credentials.yaml
db:
    host: $DB_HOST
    port: $DB_PORT
    name: $DB_NAME
    user: $DB_USER
    password: $DB_PASS

s3:
    are_local_buckets: false
    default:
        key: $S3_ACCESS_KEY
        secret: $S3_SECRET_KEY
        endpoint: http://$S3_HOST:$S3_PORT
        region: us-east-1
        bucket: $S3_BUCKET
EOF

msg_ok "✅ Credentials saved to /opt/ente/server/credentials.yaml"

# Start Ente server with Docker Compose
msg_info "Starting Ente server using prebuilt Docker image"
cd /opt/ente/server || exit

# Ensure the compose.yaml is configured to use the prebuilt image
sed -i '/build:/,/args:/d' compose.yaml
sed -i '/context:/d' compose.yaml
sed -i '/GIT_COMMIT:/d' compose.yaml

# Add image reference for museum service
sed -i 's|museum:|museum:\n    image: ghcr.io/ente-io/server|' compose.yaml

# Add "restart: always" to all services that need it
sed -i '/image: ghcr.io\/ente-io\/server/a \    restart: always' compose.yaml
sed -i '/image: postgres:15/a \    restart: always' compose.yaml
sed -i '/image: minio\/minio/a \    restart: always' compose.yaml

# Ensure museum.yaml exists (it should not be empty if required)
touch museum.yaml

# Start Docker Compose
msg_info "Running Ente server with prebuilt image"
$STD docker-compose up -d || msg_error "Docker Compose failed to start"
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
msg_info "Creating Ente Web Client Service"
cat <<EOF >/etc/systemd/system/ente-web.service
[Unit]
Description=Ente Web Client Service
After=network.target ente.service

[Service]
ExecStart=/usr/bin/bash -c "cd /opt/ente/web && git submodule update --init --recursive && yarn install && NEXT_PUBLIC_ENTE_ENDPOINT=http://localhost:8080 yarn dev"
Restart=always
User=root
WorkingDirectory=/opt/ente/web

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now ente-web.service
msg_ok "Ente Web Client Service created and started"


# Setup Message of the Day and Customizations
motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleanup completed successfully"
