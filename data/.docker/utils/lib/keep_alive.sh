#!/bin/bash
# Keep container alive while handling SIGTERM/SIGINT gracefully
# Usage: source this file at the end of entrypoint OR exec keep_alive.sh

cleanup() {
    local pids
    pids=$(jobs -p 2>/dev/null)
    [ -n "$pids" ] && kill $pids 2>/dev/null
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

while true; do
    sleep 1 &
    wait $!
done

