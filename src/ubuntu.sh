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
  read -r answer </dev/tty
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
      sudo rm -rf "${path:?}"/* 2>/dev/null || true
    else
      rm -rf "${path:?}"/* 2>/dev/null || true
    fi
    total_freed=$((total_freed + bytes))
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
}

echo
echo -e "${BOLD}=== Очистка Ubuntu ===${RESET}"
echo

# Кэш пользователя
clean_step "Кэш приложений" "$HOME/.cache"

# Корзина
clean_step "Корзина" "$HOME/.local/share/Trash" no

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

# Системные логи
echo
if ask $'\nОчистить системные логи (/var/log)? Потребуется sudo'; then
  bytes=$(dir_bytes /var/log)
  # Удаляем ротированные файлы
  sudo find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.2" -o -name "*.old" \) -delete 2>/dev/null || true
  # Активные файлы обнуляем (не удаляем — rsyslog держит дескриптор)
  sudo find /var/log -maxdepth 2 -type f -name "*.log" | while read -r f; do
    sudo truncate -s 0 "$f" 2>/dev/null || true
  done
  # syslog, auth.log, kern.log и т.п. без расширения
  for f in /var/log/syslog /var/log/auth.log /var/log/kern.log /var/log/daemon.log /var/log/messages; do
    [[ -f "$f" ]] && sudo truncate -s 0 "$f" 2>/dev/null || true
  done
  total_freed=$((total_freed + bytes))
  echo -e "  ${GREEN}Готово.${RESET}"
fi

# Сетевые логи
echo
echo -e "${BOLD}--- Сетевые логи ---${RESET}"

for svc_dir in /var/log/nginx /var/log/apache2 /var/log/httpd; do
  if [[ -d "$svc_dir" ]]; then
    svc_name=$(basename "$svc_dir")
    size=$(dir_size "$svc_dir")
    bytes=$(dir_bytes "$svc_dir")
    echo
    echo -e "${BOLD}Логи ${svc_name}${RESET} (${svc_dir})"
    echo -e "  Размер: ${RED}${size}${RESET}"
    if ask "  Очистить?"; then
      sudo find "$svc_dir" -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete 2>/dev/null || true
      sudo find "$svc_dir" -type f -name "*.log" | while read -r f; do
        sudo truncate -s 0 "$f" 2>/dev/null || true
      done
      total_freed=$((total_freed + bytes))
      echo -e "  ${GREEN}Готово.${RESET}"
    else
      echo -e "  Пропуск."
    fi
  fi
done

for svc_log in /var/log/ufw.log /var/log/fail2ban.log /var/log/NetworkManager; do
  if [[ -e "$svc_log" ]]; then
    name=$(basename "$svc_log")
    bytes=$(dir_bytes "$svc_log")
    echo
    echo -e "${BOLD}${name}${RESET}"
    echo -e "  Размер: ${RED}$(dir_size "$svc_log")${RESET}"
    if ask "  Очистить?"; then
      if [[ -d "$svc_log" ]]; then
        sudo find "$svc_log" -type f -delete 2>/dev/null || true
      else
        sudo truncate -s 0 "$svc_log" 2>/dev/null || true
      fi
      total_freed=$((total_freed + bytes))
      echo -e "  ${GREEN}Готово.${RESET}"
    else
      echo -e "  Пропуск."
    fi
  fi
done

# Journald
echo
if command -v journalctl &>/dev/null; then
  journal_size=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[KMGT]?' | tail -1 || echo "?")
  echo -e "${BOLD}Журнал systemd (journald)${RESET}"
  echo -e "  Размер: ${RED}${journal_size}${RESET}"
  if ask "  Оставить только последний день?"; then
    sudo journalctl --vacuum-time=1d 2>/dev/null || true
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
else
  echo -e "${CYAN}journalctl:${RESET} не найден, пропуск"
fi

# APT кэш
echo
if command -v apt-get &>/dev/null; then
  apt_cache="/var/cache/apt/archives"
  size=$(dir_size "$apt_cache")
  bytes=$(dir_bytes "$apt_cache")
  echo -e "${BOLD}Кэш APT${RESET} (${apt_cache})"
  echo -e "  Размер: ${RED}${size}${RESET}"
  if ask "  Очистить (apt clean)?"; then
    sudo apt-get clean 2>/dev/null || true
    total_freed=$((total_freed + bytes))
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi

  echo
  if ask "  Удалить неиспользуемые пакеты (apt autoremove)?"; then
    sudo apt-get autoremove -y 2>/dev/null || true
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
else
  echo -e "${CYAN}APT:${RESET} не найден, пропуск"
fi

# Snap — старые ревизии
echo
if command -v snap &>/dev/null; then
  echo -e "${BOLD}Snap — старые ревизии${RESET}"
  old_revs=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' || true)
  if [[ -n "$old_revs" ]]; then
    echo "$old_revs" | while read -r snap_name rev; do
      echo -e "  Найдено: ${snap_name} rev ${rev}"
    done
    if ask "  Удалить старые ревизии?"; then
      snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r snap_name rev; do
        sudo snap remove "$snap_name" --revision="$rev" 2>/dev/null || true
      done
      echo -e "  ${GREEN}Готово.${RESET}"
    else
      echo -e "  Пропуск."
    fi
  else
    echo -e "  Старых ревизий нет."
  fi
else
  echo -e "${CYAN}Snap:${RESET} не установлен, пропуск"
fi

# Docker
echo
if command -v docker &>/dev/null; then
  echo -e "${BOLD}Docker — неиспользуемые образы и контейнеры${RESET}"
  if ask "  Запустить docker system prune?"; then
    docker system prune -f 2>/dev/null || true
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
else
  echo -e "${CYAN}Docker:${RESET} не установлен, пропуск"
fi

# npm кэш
echo
if command -v npm &>/dev/null; then
  npm_cache=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
  size=$(dir_size "$npm_cache")
  bytes=$(dir_bytes "$npm_cache")
  echo -e "${BOLD}Кэш npm${RESET} (${npm_cache})"
  echo -e "  Размер: ${RED}${size}${RESET}"
  if ask "  Очистить?"; then
    npm cache clean --force 2>/dev/null || true
    total_freed=$((total_freed + bytes))
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
else
  echo -e "${CYAN}npm:${RESET} не установлен, пропуск"
fi

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
