#!/bin/bash
set -uo pipefail
# ============================================================================
# prune - Remove the odoo-env images unused for IMAGE_RETENTION_DAYS
# Internal: run by the utils entrypoint at start and once a day. Silent,
# appends one line per removed image to /var/odoo-env/prune.log.
# ============================================================================
# Images are tagged by stack (odoo-env/odoo:18.0-py3.10-latest, odoo-env/db:16)
# and shared by every project. Each start / rebuild records the date a project
# used its images (ledger); the ones no project used for IMAGE_RETENTION_DAYS
# are removed, never those of this .env nor those a container is created on.
# Dangling layers and the build cache older than that are cleaned too.
# IMAGE_RETENTION_DAYS=0 keeps everything.
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

DAYS="${IMAGE_RETENTION_DAYS:-30}"
[[ "$DAYS" =~ ^[0-9]+$ ]] || exit 0
ledger_touch_current
[ "$DAYS" -eq 0 ] && exit 0
LIMIT=$(( $(date +%s) - DAYS * 86400 ))
CURRENT=" $(odoo_image) $(db_image) $(utils_image) "
IN_USE=" $(docker ps -a --no-trunc --format '{{.Image}} {{.ImageID}}' 2>/dev/null | paste -sd' ' -) "

# tag|id|size|last-used epoch (ledger file, else image creation date)
candidates() {
    local tag id size key last
    while IFS=$'\t' read -r tag id size; do
        [ -z "$tag" ] && continue
        [[ "$CURRENT" == *" $tag "* ]] && continue
        [[ "$IN_USE" == *" $tag "* || "$IN_USE" == *" $id "* ]] && continue
        key="${LEDGER_DIR}/$(ledger_key "$tag")"
        if [ -f "$key" ]; then last=$(stat -c %Y "$key")
        else last=$(date -d "$(docker image inspect "$id" --format '{{.Created}}' 2>/dev/null)" +%s 2>/dev/null || echo 0); fi
        [ "$last" -le "$LIMIT" ] && echo "$tag|$id|$size|$last"
    done <<< "$(docker images --no-trunc --filter "reference=${IMAGE_NS}/*" --format $'{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' 2>/dev/null)"
}

OLD=$(candidates)
[ -z "$OLD" ] && exit 0
while IFS='|' read -r tag id size last; do
    docker rmi "$tag" >/dev/null 2>&1 || continue
    rm -f "${LEDGER_DIR}/$(ledger_key "$tag")"
    echo "$(date '+%F %T') removed $tag ($size, last used $(date -d "@$last" +%F))"
done <<< "$OLD"
docker image prune -f >/dev/null 2>&1
docker builder prune -f --filter "until=$((DAYS * 24))h" >/dev/null 2>&1
