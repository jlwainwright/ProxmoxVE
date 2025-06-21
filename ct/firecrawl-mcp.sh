#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2025 jlwainwright
# Author: jlwainwright
# License: MIT | https://github.com/jlwainwright/firecrawl-mcp-stack/raw/main/LICENSE
# Source: https://github.com/jlwainwright/firecrawl-mcp-stack

APP="Firecrawl MCP Stack"
var_tags="${var_tags:-firecrawl;mcp;scraping;ai;zero-trust}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-22.04}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/firecrawl-mcp-stack ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating ${APP}"
    cd /opt/firecrawl-mcp-stack
    $STD git pull origin main
    $STD docker compose pull
    $STD docker compose up -d --force-recreate
    msg_ok "Updated ${APP}"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access via your zero trust network${CL}"
echo -e "${INFO}${YW} Documentation: https://github.com/jlwainwright/firecrawl-mcp-stack${CL}"