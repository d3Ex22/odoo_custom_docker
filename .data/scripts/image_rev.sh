#!/bin/bash
# ============================================================================
# image_rev.sh odoo|utils [PROJECT_ROOT] — 8-hex revision of that image's
# Dockerfile (the only file baked into it).
#
# The revision is part of the image tag (ODOO_IMAGE_REV / UTILS_IMAGE_REV in
# .env, maintained by the utils entrypoint and 'rebuild'): a project only runs
# an image built from its own files, and two projects whose .data differ never
# overwrite each other's images. Scripts, entrypoints and the web terminal are
# mounted, not copied, so editing them never changes the revision.
# ============================================================================
SERVICE="${1:-}"
ROOT="${2:-/home/utils/odoo_custom_docker}"
case "$SERVICE" in
    odoo|utils) ;;
    *) echo "usage: image_rev.sh odoo|utils [PROJECT_ROOT]" >&2; exit 1 ;;
esac
cd "$ROOT" || exit 1
sha256sum < ".data/docker/${SERVICE}/Dockerfile" 2>/dev/null | cut -c1-8
