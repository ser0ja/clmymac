#!/usr/bin/env bash

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

total_freed=0

# Дополнительные директории для очистки (редактируй по необходимости)
EXTRA_DIRS=()

dir_size() {
  du -sh "$1" 2>/dev/null | cut -f1
}

dir_bytes() {
  du -sk "$1" 2>/dev/null | cut -f1
}

ask() {
  local prompt="$1"
  echo -en "${YELLOW}${prompt} [y/N] ${RESET}"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

clean_step() {
  local name="$1"
  local path="$2"
  local use_sudo="${3:-no}"

  if [[ ! -e "$path" ]]; then
    echo -e "${CYAN}${name}:${RESET} директория не найдена, пропуск"
    return
  fi

  local size
  size=$(dir_size "$path")
  local bytes
  bytes=$(dir_bytes "$path")

  echo
  echo -e "${BOLD}${name}${RESET} (${path})"
  echo -e "  Размер: ${RED}${size}${RESET}"

  if ask "  Очистить?"; then
    if [[ "$use_sudo" == "sudo" ]]; then
      sudo rm -rf "${path:?}"/*  2>/dev/null || true
    else
      rm -rf "${path:?}"/*  2>/dev/null || true
    fi
    total_freed=$((total_freed + bytes))
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
}

echo
echo -e "${BOLD}=== Очистка macOS ===${RESET}"
echo

# Кэш пользователя
clean_step "Кэш приложений" "$HOME/Library/Caches"

# Логи пользователя
clean_step "Логи приложений" "$HOME/Library/Logs"

# Системные логи (нужен sudo)
if ask $'\nОчистить системные логи (/var/log)? Потребуется sudo'; then
  bytes=$(dir_bytes /var/log)
  sudo find /var/log -type f -name "*.log" -delete 2>/dev/null || true
  total_freed=$((total_freed + bytes))
  echo -e "  ${GREEN}Готово.${RESET}"
fi

# Корзина
echo
echo -e "${BOLD}Корзина${RESET}"
if ask "  Очистить?"; then
  osascript -e 'tell application "Finder" to empty trash' 2>/dev/null || true
  echo -e "  ${GREEN}Готово.${RESET}"
else
  echo -e "  Пропуск."
fi

# /tmp
echo
if [[ -d /tmp ]]; then
  size=$(dir_size /tmp)
  bytes=$(dir_bytes /tmp)
  echo -e "${BOLD}Временные файлы${RESET} (/tmp)"
  echo -e "  Размер: ${RED}${size}${RESET}"
  if ask "  Очистить?"; then
    sudo find /tmp -mindepth 1 -delete 2>/dev/null || true
    total_freed=$((total_freed + bytes))
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
fi

# Homebrew
echo
if command -v brew &>/dev/null; then
  cache_path=$(brew --cache 2>/dev/null || echo "")
  if [[ -n "$cache_path" && -d "$cache_path" ]]; then
    size=$(dir_size "$cache_path")
    bytes=$(dir_bytes "$cache_path")
    echo -e "${BOLD}Кэш Homebrew${RESET} (${cache_path})"
    echo -e "  Размер: ${RED}${size}${RESET}"
    if ask "  Очистить?"; then
      brew cleanup --prune=all -s 2>/dev/null || true
      total_freed=$((total_freed + bytes))
      echo -e "  ${GREEN}Готово.${RESET}"
    else
      echo -e "  Пропуск."
    fi
  fi
else
  echo -e "${CYAN}Homebrew:${RESET} не установлен, пропуск"
fi

# Системный кэш
clean_step "Системный кэш" "/Library/Caches" sudo

# macOS temp (/private/var/folders)
echo
if [[ -d /private/var/folders ]]; then
  size=$(dir_size /private/var/folders)
  bytes=$(dir_bytes /private/var/folders)
  echo -e "${BOLD}macOS temp${RESET} (/private/var/folders)"
  echo -e "  Размер: ${RED}${size}${RESET}"
  if ask "  Очистить?"; then
    sudo find /private/var/folders -mindepth 1 -maxdepth 3 -name "*.lock" -o -name "*.tmp" -delete 2>/dev/null || true
    total_freed=$((total_freed + bytes))
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
fi

# Xcode
echo
echo -e "${BOLD}--- Xcode ---${RESET}"
clean_step "DerivedData" "$HOME/Library/Developer/Xcode/DerivedData"
clean_step "Archives" "$HOME/Library/Developer/Xcode/Archives"
clean_step "CoreSimulator" "$HOME/Library/Developer/CoreSimulator" sudo

# Android
echo
echo -e "${BOLD}--- Android ---${RESET}"
clean_step "Android SDK/AVD" "$HOME/Library/Android"
clean_step "Android кэш" "$HOME/.android/cache"

# Кэши сборки
echo
echo -e "${BOLD}--- Кэши сборки ---${RESET}"
clean_step "Gradle" "$HOME/.gradle/caches"
clean_step "Cargo (registry)" "$HOME/.cargo/registry"
clean_step "Go modules" "$HOME/go/pkg/mod/cache"
clean_step "npm" "$HOME/.npm"
clean_step "pnpm" "$HOME/Library/pnpm/store"

# Docker
echo
if command -v docker &>/dev/null; then
  echo -e "${BOLD}Docker — неиспользуемые данные${RESET}"
  if ask "  Запустить docker system prune?"; then
    docker system prune -f 2>/dev/null || true
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
else
  echo -e "${CYAN}Docker:${RESET} не установлен, пропуск"
fi

# Виртуальные машины
echo
echo -e "${BOLD}--- Виртуальные машины ---${RESET}"
clean_step "Parallels" "$HOME/Parallels"
clean_step "VMware" "$HOME/Virtual Machines"
clean_step "UTM" "$HOME/Library/Containers/com.utmapp.UTM"
clean_step "Colima" "$HOME/.colima"

# Дополнительные директории
if (( ${#EXTRA_DIRS[@]} > 0 )); then
  echo
  echo -e "${BOLD}--- Дополнительные директории ---${RESET}"
  for dir in "${EXTRA_DIRS[@]}"; do
    clean_step "$(basename "$dir")" "$dir" sudo
  done
fi

echo
echo -e "${BOLD}=== Завершено ===${RESET}"
if (( total_freed > 0 )); then
  freed_mb=$(( total_freed / 1024 ))
  echo -e "Освобождено примерно: ${GREEN}${freed_mb} МБ${RESET}"
fi
echo
