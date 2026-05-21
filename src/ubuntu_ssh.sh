#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read -rp "Хост [127.0.0.1]: " REMOTE
REMOTE="${REMOTE:-10.0.0.100}"

read -rp "Порт [22]: " PORT
PORT="${PORT:-22}"

read -rp "Пользователь [$(whoami)]: " USER
USER="${USER:-$(whoami)}"
CTRL="/tmp/ssh_ctl_$$"

cleanup() {
  ssh -S "$CTRL" -O exit "${USER}@${REMOTE}" 2>/dev/null || true
}
trap cleanup EXIT

echo "Подключение к ${REMOTE}:${PORT} (введи пароль один раз)..."
ssh -M -S "$CTRL" -f -N -p "$PORT" "${USER}@${REMOTE}"

echo "Копирование скрипта..."
scp -o "ControlPath=$CTRL" -P "$PORT" "$SCRIPT_DIR/ubuntu.sh" "${USER}@${REMOTE}:/tmp/ubuntu.sh"

ssh -t -S "$CTRL" -p "$PORT" "${USER}@${REMOTE}" "bash /tmp/ubuntu.sh; rm -f /tmp/ubuntu.sh"
