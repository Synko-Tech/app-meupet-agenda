#!/usr/bin/env bash
# Encerra o Firebase Emulator Suite local de desenvolvimento.
#
# Uso:
#   scripts/stop-dev.sh
set -euo pipefail

echo "==> Encerrando emuladores Firebase (projeto meupet-agenda-app)..."
pkill -f "firebase emulators:start --project meupet-agenda-app" 2>/dev/null || true
sleep 2

for port in 5001 8080 9099 9199 4000; do
  if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${port}/" 2>/dev/null; then
    echo "Aviso: porta $port ainda responde."
  fi
done

echo "==> Emuladores encerrados."
