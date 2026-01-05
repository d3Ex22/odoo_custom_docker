#!/bin/bash

# Detect host project directory from Docker volume mount
detect_host_project_dir() {
    local mount_point="/home/odoo/docker_dev"
    local host_path=""
    
    # Get container ID from hostname (Docker sets hostname to container ID)
    local container_id=$(hostname 2>/dev/null)
    
    # Try docker inspect to get the real host path
    if [ -n "$container_id" ] && command -v docker &> /dev/null; then
        host_path=$(docker inspect "$container_id" 2>/dev/null | grep -B2 "\"Destination\": \"${mount_point}\"" | grep "\"Source\"" | sed 's/.*"Source": "\(.*\)".*/\1/' | tr -d ',' | xargs)
    fi
    
    # Fallback to environment variable
    if [ -z "$host_path" ] || [ "$host_path" = "." ]; then
        host_path="$HOST_PROJECT_DIR"
    fi
    
    # Final fallback
    if [ -z "$host_path" ] || [ "$host_path" = "." ]; then
        host_path="/unknown"
    fi
    
    echo "$host_path"
}
HOST_PROJECT_DIR=$(detect_host_project_dir)
echo "$HOST_PROJECT_DIR" > /home/odoo/docker_dev/data/.host_project_dir

source /home/odoo/docker_dev/.env 2>/dev/null
source /home/odoo/docker_dev/data/.docker/utils/theme.conf 2>/dev/null
source /home/odoo/docker_dev/data/.docker/utils/ui.sh 2>/dev/null
COLOR="${UTILS_COLOR:-#0abdc6}"
R=$((16#${COLOR:1:2}))
G=$((16#${COLOR:3:2}))
B=$((16#${COLOR:5:2}))
C="\033[38;2;${R};${G};${B}m"
RST="\033[0m"

# Ensure command scripts are executable (mounted from host)
find /home/odoo/docker_dev/data/.docker/utils/commands -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null

cat > /home/odoo/.welcome << EOF
clear
echo ""
echo " Available commands (--help for details):"
echo ""
echo "  Odoo:"
printf "   ${C}(r)  ${RST}reboot                        ${C}Restart Odoo                  ${RST}\n"
printf "   ${C}     ${RST}shell [db]                    ${C}Odoo shell (new pane)         ${RST}\n"
printf "   ${C}(s)  ${RST}start                         ${C}Start Odoo process            ${RST}\n"
printf "   ${C}     ${RST}stop                          ${C}Stop Odoo process             ${RST}\n"
printf "   ${C}(u)  ${RST}update [module]               ${C}Update module(s) and restart  ${RST}\n"
echo ""
echo "  Database:"
printf "   ${C}     ${RST}cheat                         ${C}Bypass Odoo expiration        ${RST}\n"
printf "   ${C}(db) ${RST}database [command]            ${C}Database management           ${RST}\n"
printf "   ${C}     ${RST}fix-reports [--force]         ${C}Fix report.url in DB          ${RST}\n"
printf "   ${C}     ${RST}psql [--database db]          ${C}PostgreSQL shell              ${RST}\n"
echo ""
echo "  Migration:"
printf "   ${C}     ${RST}migrate <db> <version>        ${C}Migrate database via Odoo     ${RST}\n"
printf "   ${C}     ${RST}upgrade-code --from VER       ${C}Migrate code (19.0+ only)     ${RST}\n"
echo ""
echo "  Docker:"
printf "   ${C}     ${RST}rebuild [--no-cache] [--all]  ${C}Rebuild containers            ${RST}\n"
printf "   ${C}     ${RST}set <VAR> [value]             ${C}Configure .env settings       ${RST}\n"
printf "   ${C}     ${RST}status                        ${C}Container status              ${RST}\n"
echo ""
echo "  Tools:"
printf "   ${C}     ${RST}check_versions                ${C}Installed versions            ${RST}\n"
printf "   ${C}     ${RST}grok                          ${C}Ngrok tunnel                  ${RST}\n"
printf "   ${C}     ${RST}help                          ${C}Show this help                ${RST}\n"
printf "   ${C}     ${RST}pip <command>                 ${C}Pip in Odoo container         ${RST}\n"
printf "   ${C}(pc) ${RST}pre-commit                    ${C}Run pre-commit hooks          ${RST}\n"
printf "   ${C}     ${RST}requirements                  ${C}Install addons requirements   ${RST}\n"
printf "   ${C}     ${RST}test-ui                       ${C}Demo UI components (Gum)      ${RST}\n"
echo ""
EOF
chown odoo:odoo /home/odoo/.welcome

exec tail -f /dev/null
