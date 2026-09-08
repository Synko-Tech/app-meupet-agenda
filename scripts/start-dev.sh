#!/usr/bin/env bash
# Sobe o Firebase Emulator Suite para desenvolvimento local com o MESMO
# project id do app (meupet-agenda-app). O app em debug fala com os
# emuladores por padrao (kDebugMode), e o emulador de Functions roteia por
# project id: iniciar com outro projeto faz os callables retornarem 404
# ("Servico indisponivel no momento.").
#
# Uso:
#   scripts/start-dev.sh          # sobe + seed
#   scripts/start-dev.sh --no-seed
#
# O emulador fica em primeiro plano: rode num terminal dedicado e deixe
# aberto enquanto usa o app. Encerre com Ctrl+C (ou scripts/stop-dev.sh).
set -euo pipefail

PROJECT_ID="${FIREBASE_PROJECT_ID:-meupet-agenda-app}"
EMULATORS="auth,firestore,storage,functions"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Iniciando emuladores do projeto '$PROJECT_ID' (aguarde 'All emulators ready!')"
firebase emulators:start --project "$PROJECT_ID" --only "$EMULATORS" &
EMU_PID=$!

# Aguarda as portas dos emuladores ficarem prontas.
for port in 5001 8080 9099 9199; do
  for _ in $(seq 1 60); do
    if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${port}/" 2>/dev/null; then
      break
    fi
    sleep 1
  done
done
sleep 2

if [[ "${1:-}" == "--no-seed" ]]; then
  echo "==> Emuladores prontos (sem seed)."
  wait "$EMU_PID"
  exit 0
fi

echo "==> Semeando dados de teste (users alice/admin1, loja biz1)..."
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
  node "$ROOT/functions/seed-emulator.js"

echo ""
echo "==> Ambiente de desenvolvimento pronto!"
echo "    - Emulador UI:      http://127.0.0.1:4000"
echo "    - Contas de teste:  alice@exemplo.com / senha-forte-123"
echo "                         admin@exemplo.com / senha-forte-admin"
echo "    - Hot restart no app: tecla R no terminal do 'flutter run'"
wait "$EMU_PID"
