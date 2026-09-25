#!/bin/bash
set -e
HOST=${REDROID_HOST:-redroid}
PORT=${REDROID_ADB_PORT:-5555}

adb start-server

echo "waiting for $HOST:$PORT ..."
for i in $(seq 1 60); do
  if (echo > /dev/tcp/$HOST/$PORT) 2>/dev/null; then
    echo "tcp open"
    break
  fi
  sleep 2
done

adb connect "$HOST:$PORT" || true
adb devices -l

# ws-scrcpy defaults to port 8000, no auth
exec npm start
