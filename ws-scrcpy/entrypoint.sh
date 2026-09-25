#!/bin/bash
set -e

# Space-separated list of "host:port" adb endpoints.
HOSTS=${REDROID_HOSTS:-${REDROID_HOST:-redroid}:${REDROID_ADB_PORT:-5555}}

adb start-server

for hp in $HOSTS; do
  host=${hp%:*}
  port=${hp#*:}
  echo "waiting for $host:$port ..."
  for i in $(seq 1 60); do
    if (echo > /dev/tcp/$host/$port) 2>/dev/null; then
      echo "tcp open: $host:$port"
      break
    fi
    sleep 2
  done
  adb connect "$host:$port" || true
done

adb devices -l

# ws-scrcpy tracks every device on the local adb server.
exec npm start
