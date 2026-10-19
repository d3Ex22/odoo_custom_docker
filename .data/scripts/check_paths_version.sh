#!/bin/bash
# ============================================================================
# Verify that the mounted Enterprise / Odoo source folders match ODOO_VERSION.
# Runs inside the odoo container (also called from utils via docker exec).
#
#   check_paths_version.sh          check mode: prints errors, exit 1 on mismatch
#   check_paths_version.sh --print  prints "enterprise=<ver|none|unknown>" "odoo=<ver|none|unknown>"
#                                   (none = folder not mounted/empty, unknown = not detectable)
#
# A 17.0 enterprise folder loaded by a 19.0 server silently corrupts the
# database on -u, so Odoo must not start when the versions differ.
# ============================================================================

ENTERPRISE_DIR="/mnt/enterprise-addons"
ODOO_SRC_DIR="/mnt/odoo-src"
WANTED="${ODOO_VERSION:-}"
[ -z "$WANTED" ] && [ -f /home/odoo/.env ] && WANTED=$(grep -E '^ODOO_VERSION=' /home/odoo/.env | cut -d= -f2 | tr -d "\"' ")

# Enterprise manifests carry no series prefix ('version': '1.0'), so the only
# reliable marker is the checked-out git branch: 19.0, 18.0, saas-19.2...
# Not a git repo (or detached HEAD) → unknown, no check possible.
git_branch_version() {
    local dir="$1" head ref
    local gitdir="$dir/.git"
    [ -f "$gitdir" ] && gitdir=$(sed -n 's/^gitdir: //p' "$gitdir")      # worktree / submodule
    [ -f "$gitdir/HEAD" ] || return
    head=$(cat "$gitdir/HEAD")
    ref=$(echo "$head" | sed -n 's|^ref: refs/heads/||p')
    [[ "$ref" =~ ^(saas-)?[0-9]+\.[0-9]+$ ]] && echo "${ref/saas-/saas~}"
}
enterprise_version() {
    [ -d "$ENTERPRISE_DIR" ] || return
    ls "$ENTERPRISE_DIR"/*/__manifest__.py >/dev/null 2>&1 || return
    local v; v=$(git_branch_version "$ENTERPRISE_DIR")
    echo "${v:-unknown}"
}

# odoo/release.py: version_info = (19, 0, 0, FINAL, 0, '')  or  ('saas~17', 4, ...)
odoo_version() {
    local rel="$ODOO_SRC_DIR/odoo/release.py"
    [ -f "$rel" ] || return
    local major minor
    major=$(grep -oE "^version_info[[:space:]]*=[[:space:]]*\([[:space:]]*'?(saas~)?[0-9]+" "$rel" | grep -oE "(saas~)?[0-9]+$")
    minor=$(grep -oE "^version_info[[:space:]]*=[[:space:]]*\([[:space:]]*'?(saas~)?[0-9]+'?,[[:space:]]*[0-9]+" "$rel" | grep -oE "[0-9]+$")
    [ -n "$major" ] && echo "${major}.${minor:-0}" || echo "unknown"
}

ENT=$(enterprise_version)
SRC=$(odoo_version)

if [ "${1:-}" = "--print" ]; then
    echo "enterprise=${ENT:-none}"
    echo "odoo=${SRC:-none}"
    exit 0
fi

[ -z "$WANTED" ] && exit 0
rc=0
if [ -n "$ENT" ] && [ "$ENT" != "unknown" ] && [ "$ENT" != "$WANTED" ]; then
    echo "ENTERPRISE_PATH is Odoo ${ENT}, the server is ${WANTED}"
    rc=1
fi
if [ -n "$SRC" ] && [ "$SRC" != "unknown" ] && [ "$SRC" != "$WANTED" ]; then
    echo "ODOO_PATH is Odoo ${SRC}, the server is ${WANTED}"
    rc=1
fi
exit $rc
