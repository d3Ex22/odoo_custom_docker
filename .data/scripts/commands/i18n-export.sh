#!/bin/bash
# Backward-compatible wrapper — use `translation` instead.
exec "$(dirname "$0")/translation.sh" "$@"
