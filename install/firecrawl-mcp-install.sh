#!/usr/bin/env bash

# Copyright (c) 2025 jlwainwright
# Author: jlwainwright
# License: MIT | https://github.com/jlwainwright/firecrawl-mcp-stack/raw/main/LICENSE
# Source: https://github.com/jlwainwright/firecrawl-mcp-stack

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

get_latest_release() {
  curl -fsSL https://api.github.com/repos/"$1"/releases/latest | grep '"tag_name":' | cut -d'"' -f4
}

FIRECRAWL_LATEST_VERSION=$(get_latest_release "mendableai/firecrawl")

msg_info "Installing Dependencies"
$STD apt-get install -y \
    curl \
    wget \
    git \
    openssl \
    ca-certificates \
    gnupg \
    lsb-release
msg_ok "Installed Dependencies"

msg_info "Installing Docker"
mkdir -p /etc/docker
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -fsSL https://get.docker.com)
$STD systemctl enable docker
$STD systemctl start docker
msg_ok "Installed Docker"

msg_info "Installing Docker Compose"
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
$STD curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
$STD chmod +x /usr/local/bin/docker-compose
msg_ok "Installed Docker Compose"

msg_info "Cloning Firecrawl MCP Stack Repository"
cd /opt
$STD git clone https://github.com/jlwainwright/firecrawl-mcp-stack.git
cd firecrawl-mcp-stack
$STD chmod +x scripts/*.sh
msg_ok "Cloned Repository"

msg_info "Generating Secure Credentials"
cp .env.production.template .env.production

# Generate secure credentials
FIRECRAWL_API_KEY=$(openssl rand -hex 32)
GOTRUE_JWT_SECRET=$(openssl rand -hex 64)
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
SECRET_KEY_BASE=$(openssl rand -hex 64)
MCP_AUTH_TOKEN=$(openssl rand -hex 32)
BULL_AUTH_KEY=$(openssl rand -hex 32)

# Replace placeholders in .env.production
sed -i "s/REPLACE_WITH_SECURE_32_CHAR_HEX_KEY/$FIRECRAWL_API_KEY/g" .env.production
sed -i "s/REPLACE_WITH_SECURE_64_CHAR_HEX_SECRET/$GOTRUE_JWT_SECRET/g" .env.production
sed -i "s/REPLACE_WITH_SECURE_DATABASE_PASSWORD/$POSTGRES_PASSWORD/g" .env.production
sed -i "s/REPLACE_WITH_SECURE_64_CHAR_SECRET_KEY_BASE/$SECRET_KEY_BASE/g" .env.production
sed -i "s/REPLACE_WITH_SECURE_MCP_AUTH_TOKEN/$MCP_AUTH_TOKEN/g" .env.production
sed -i "s/REPLACE_WITH_SECURE_BULL_AUTH_KEY/$BULL_AUTH_KEY/g" .env.production

# Copy to active environment
cp .env.production .env
msg_ok "Generated Secure Credentials"

# Ask user for zero trust preference
echo -e "\n${TAB3}Choose Zero Trust Deployment:"
echo -e "${TAB3}1) Tailscale (Mesh VPN) - Recommended"
echo -e "${TAB3}2) Cloudflare Zero Trust (Web-based)"
echo -e "${TAB3}3) Local Development (Testing Only)"
read -r -p "${TAB3}Choose [1]: " deployment_choice

case $deployment_choice in
    2)
        DEPLOYMENT_TYPE="cloudflare"
        echo -e "${TAB3}${YW}Cloudflare Zero Trust selected${CL}"
        echo -e "${TAB3}${YW}You'll need to configure tunnel token and domain after deployment${CL}"
        ;;
    3)
        DEPLOYMENT_TYPE="local"
        echo -e "${TAB3}${YW}Local development mode selected${CL}"
        echo -e "${TAB3}${RD}WARNING: This exposes ports publicly - NOT for production!${CL}"
        ;;
    *)
        DEPLOYMENT_TYPE="tailscale"
        echo -e "${TAB3}${YW}Tailscale selected${CL}"
        echo -e "${TAB3}${YW}You'll need to configure auth key after deployment${CL}"
        ;;
esac

if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
    msg_info "Starting Firecrawl MCP Stack (Local Development)"
    $STD docker compose up -d
    msg_ok "Started Firecrawl MCP Stack"
else
    msg_info "Building MCP Server"
    if [[ "$DEPLOYMENT_TYPE" == "tailscale" ]]; then
        $STD docker compose -f docker-compose.tailscale.yaml build mcp-server
    else
        $STD docker compose -f docker-compose.cloudflare.yaml build mcp-server
    fi
    msg_ok "Built MCP Server"
    
    echo -e "${TAB3}${YW}Zero trust setup required - services not started yet${CL}"
fi

# Create management alias
cat > /usr/local/bin/firecrawl-manage << 'EOF'
#!/bin/bash
cd /opt/firecrawl-mcp-stack
case "$1" in
    status)
        ./scripts/monitor.sh status
        ;;
    logs)
        ./scripts/monitor.sh logs "${2:-}"
        ;;
    restart)
        ./scripts/monitor.sh restart "${2:-}"
        ;;
    backup)
        ./scripts/monitor.sh backup
        ;;
    tailscale)
        if [ -z "$TAILSCALE_AUTH_KEY" ]; then
            echo "Set TAILSCALE_AUTH_KEY environment variable first"
            echo "export TAILSCALE_AUTH_KEY=tskey-auth-YOUR_KEY"
            exit 1
        fi
        ./scripts/deploy-tailscale.sh
        ;;
    cloudflare)
        if [ -z "$CF_TUNNEL_TOKEN" ] || [ -z "$CF_DOMAIN" ]; then
            echo "Set required environment variables first:"
            echo "export CF_TUNNEL_TOKEN=your_tunnel_token"
            echo "export CF_DOMAIN=yourdomain.com"
            exit 1
        fi
        ./scripts/deploy-cloudflare.sh
        ;;
    *)
        echo "Firecrawl MCP Stack Management"
        echo "Usage: firecrawl-manage [command]"
        echo ""
        echo "Commands:"
        echo "  status              Show service status"
        echo "  logs [service]      Show service logs"
        echo "  restart [service]   Restart services"
        echo "  backup              Create backup"
        echo "  tailscale           Complete Tailscale setup"
        echo "  cloudflare          Complete Cloudflare setup"
        echo ""
        echo "Zero Trust Setup:"
        echo "  export TAILSCALE_AUTH_KEY=tskey-auth-YOUR_KEY"
        echo "  firecrawl-manage tailscale"
        echo ""
        echo "  export CF_TUNNEL_TOKEN=your_token"
        echo "  export CF_DOMAIN=yourdomain.com"
        echo "  firecrawl-manage cloudflare"
        ;;
esac
EOF

chmod +x /usr/local/bin/firecrawl-manage

msg_info "Creating Systemd Service"
cat > /etc/systemd/system/firecrawl-mcp.service << EOF
[Unit]
Description=Firecrawl MCP Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/firecrawl-mcp-stack
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl enable firecrawl-mcp.service
msg_ok "Created Systemd Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

echo -e "\n🔒 ${GN}Firecrawl MCP Zero Trust Stack Installation Complete!${CL}\n"
echo -e "📋 ${YW}Credentials stored in: /opt/firecrawl-mcp-stack/.env.production${CL}"
echo -e "🔑 ${YW}API Key: $FIRECRAWL_API_KEY${CL}"
echo -e "🔑 ${YW}MCP Token: $MCP_AUTH_TOKEN${CL}\n"

if [[ "$DEPLOYMENT_TYPE" == "local" ]]; then
    echo -e "🌐 ${GN}Local Access (Development Only):${CL}"
    echo -e "   Firecrawl API:    http://$(hostname -I | awk '{print $1}'):3002"
    echo -e "   MCP Server:       http://$(hostname -I | awk '{print $1}'):3003"
    echo -e "   Supabase Studio:  http://$(hostname -I | awk '{print $1}'):3001"
    echo -e "\n${RD}⚠️  WARNING: Ports exposed publicly - secure with firewall!${CL}\n"
else
    echo -e "🔗 ${YW}Zero Trust Setup Required:${CL}"
    if [[ "$DEPLOYMENT_TYPE" == "tailscale" ]]; then
        echo -e "   1. Get auth key: https://login.tailscale.com/admin/settings/keys"
        echo -e "   2. Run: export TAILSCALE_AUTH_KEY=tskey-auth-YOUR_KEY"
        echo -e "   3. Run: firecrawl-manage tailscale"
        echo -e "\n   Access via: http://firecrawl-stack:3002 (after setup)"
    else
        echo -e "   1. Get tunnel token from Cloudflare Zero Trust Dashboard"
        echo -e "   2. Run: export CF_TUNNEL_TOKEN=your_token"
        echo -e "   3. Run: export CF_DOMAIN=yourdomain.com"
        echo -e "   4. Run: firecrawl-manage cloudflare"
        echo -e "\n   Access via: https://api.yourdomain.com (after setup)"
    fi
fi

echo -e "\n📊 ${YW}Management Commands:${CL}"
echo -e "   firecrawl-manage status      # Service status"
echo -e "   firecrawl-manage logs        # View logs"
echo -e "   firecrawl-manage backup      # Create backup"
echo -e "\n📚 ${YW}Documentation: https://github.com/jlwainwright/firecrawl-mcp-stack${CL}"