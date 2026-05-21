#!/usr/bin/env bash

set -uo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

added=0

exclude() {
  if [[ ! -e "$1" ]]; then
    echo -e "  ${YELLOW}-${RESET} $1 (не существует)"
    return 0
  fi
  if sudo tmutil addexclusion -p "$1"; then
    echo -e "  ${GREEN}+${RESET} $1"
    (( added++ )) || true
  else
    echo -e "  ${RED}!${RESET} $1 (ошибка tmutil)"
  fi
}

exclude_glob() {
  for path in $1; do
    if [[ ! -e "$path" ]]; then
      echo -e "  ${YELLOW}-${RESET} $path (не существует)"
      continue
    fi
    if sudo tmutil addexclusion -p "$path"; then
      echo -e "  ${GREEN}+${RESET} $path"
      (( added++ )) || true
    else
      echo -e "  ${RED}!${RESET} $path (ошибка tmutil)"
    fi
  done
}

echo
echo -e "${BOLD}=== Исключения из Time Machine ===${RESET}"

echo
echo -e "${BOLD}Системные кэши и логи${RESET}"
exclude "$HOME/Library/Caches"
exclude "$HOME/Library/Logs"
exclude "/Library/Caches"
exclude "/private/var/log"
exclude "/private/var/folders"

echo
echo -e "${BOLD}Облачные хранилища${RESET}"
exclude "$HOME/Library/CloudStorage"
exclude "$HOME/Library/Mobile Documents"

echo
echo -e "${BOLD}Xcode / iOS${RESET}"
exclude "$HOME/Library/Developer/Xcode/DerivedData"
exclude "$HOME/Library/Developer/Xcode/Archives"
exclude "$HOME/Library/Developer/CoreSimulator"

echo
echo -e "${BOLD}Android${RESET}"
exclude "$HOME/Library/Android"

echo
echo -e "${BOLD}Кэши сборки${RESET}"
exclude "$HOME/.gradle"
exclude "$HOME/.npm"
exclude "$HOME/.cache"
exclude "$HOME/.cargo"
exclude "$HOME/go/pkg"
exclude "$HOME/Library/pnpm"
exclude "$HOME/Library/Caches/Homebrew"

echo
echo -e "${BOLD}Docker${RESET}"
exclude_glob "$HOME/Library/Group Containers/*.com.docker"
exclude "$HOME/Library/Containers/com.docker.docker"
exclude "$HOME/.docker"
exclude "$HOME/.colima"

echo
echo -e "${BOLD}Виртуальные машины${RESET}"
exclude "$HOME/Parallels"
exclude "$HOME/Virtual Machines"
exclude "$HOME/Library/Containers/com.utmapp.UTM"

echo
echo -e "${BOLD}Добавлено исключений: ${GREEN}${added}${RESET}"
echo
