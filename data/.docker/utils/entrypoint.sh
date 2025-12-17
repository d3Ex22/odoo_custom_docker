#!/bin/bash

# Always update host project directory (in case path changed)
echo "$HOST_PROJECT_DIR" > /home/odoo/docker_dev/data/.host_project_dir

source /home/odoo/docker_dev/.env 2>/dev/null
source /home/odoo/docker_dev/data/.docker/utils/config/theme.conf 2>/dev/null
COLOR="${UTILS_COLOR:-#0abdc6}"
R=$((16#${COLOR:1:2}))
G=$((16#${COLOR:3:2}))
B=$((16#${COLOR:5:2}))
C="\033[38;2;${R};${G};${B}m"
RST="\033[0m"

# Ensure all .sh scripts in project are executable (mounted from host)
find /home/odoo/docker_dev/data/.docker -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null

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

exec /home/odoo/docker_dev/data/.docker/utils/lib/keep_alive.sh
