#!/usr/bin/env bash

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

total_freed=0
disk_avail_start=$(df -k / | awk 'NR==2 {print $4}')

# Дополнительные директории для очистки (редактируй по необходимости)
EXTRA_DIRS=()

dir_size() {
  du -sh "$1" 2>/dev/null | cut -f1
}

dir_bytes() {
  local kb
  kb=$(du -sk "$1" 2>/dev/null | cut -f1)
  echo "${kb:-0}"
}

human_size() {
  awk -v b="${1:-0}" 'BEGIN {
    if (b <= 0) printf "?"
    else if (b >= 1073741824) printf "%.1f ГБ", b / 1073741824
    else if (b >= 1048576) printf "%.0f МБ", b / 1048576
    else printf "%d Б", b
  }'
}

ask() {
  local prompt="$1"
  echo -en "${YELLOW}${prompt} [y/N] ${RESET}"
  read -r answer
  answer=$(printf '%s' "$answer" | LC_ALL=C tr -cd 'a-zA-Z' | tr '[:upper:]' '[:lower:]')
  [[ "$answer" == "y" ]]
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
    local after
    after=$(dir_bytes "$path")
    total_freed=$((total_freed + bytes - after))
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
  # Ротированные/сжатые логи + старые .log (активные .log держат демоны — их не трогаем)
  sudo find /var/log -type f \( -name "*.gz" -o -name "*.bz2" -o -name "*.[0-9]" \) -delete 2>/dev/null || true
  sudo find /var/log -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true
  after=$(dir_bytes /var/log)
  total_freed=$((total_freed + bytes - after))
  echo -e "  ${GREEN}Готово.${RESET}"
fi

# Корзина
echo
echo -e "${BOLD}Корзина${RESET} ($HOME/.Trash)"
echo -e "  Размер: ${RED}$(dir_size "$HOME/.Trash")${RESET}"
if ask "  Очистить?"; then
  bytes=$(dir_bytes "$HOME/.Trash")
  osascript -e 'tell application "Finder" to empty trash' 2>/dev/null || true
  after=$(dir_bytes "$HOME/.Trash")
  total_freed=$((total_freed + bytes - after))
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
    after=$(dir_bytes /tmp)
    total_freed=$((total_freed + bytes - after))
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
      after=$(dir_bytes "$cache_path")
      total_freed=$((total_freed + bytes - after))
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
  echo -e "${BOLD}macOS temp${RESET} (/private/var/folders, удаляются только *.tmp)"
  echo -e "  Размер: ${RED}${size}${RESET}"
  if ask "  Очистить?"; then
    sudo find /private/var/folders -mindepth 1 -maxdepth 3 -name "*.tmp" -delete 2>/dev/null || true
    after=$(dir_bytes /private/var/folders)
    total_freed=$((total_freed + bytes - after))
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
clean_step "Xcode Products" "$HOME/Library/Developer/Xcode/Products"
clean_step "iOS DeviceSupport" "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
clean_step "watchOS DeviceSupport" "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"
clean_step "tvOS DeviceSupport" "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"
clean_step "CoreSimulator Caches" "$HOME/Library/Developer/CoreSimulator/Caches"
clean_step "CoreSimulator" "$HOME/Library/Developer/CoreSimulator" sudo

# simctl из активного toolchain; фолбэк на Xcode.app,
# если xcode-select указывает на CommandLineTools
SIMCTL=$(xcrun --find simctl 2>/dev/null || true)
if [[ -z "$SIMCTL" && -x "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl" ]]; then
  SIMCTL="/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"
fi

if [[ -z "$SIMCTL" ]]; then
  echo
  echo -e "${CYAN}simctl:${RESET} не найден, шаги симуляторов пропущены"
else
  # Удалить недоступные симуляторы (после обновлений Xcode/iOS)
  echo
  echo -e "${BOLD}Недоступные симуляторы${RESET}"
  if ask "  Удалить (simctl delete unavailable)?"; then
    "$SIMCTL" delete unavailable 2>/dev/null || true
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi

  # ВНИМАНИЕ (спорные): runtime-образы — не кэш, а сами системы для симулятора.
  # Лежат в /Library/Developer/CoreSimulator/Images и
  # /System/Library/AssetsV2/com_apple_MobileAsset_*SimulatorRuntime.
  # Удалять только через simctl: rm -rf оставит битую регистрацию в CoreSimulator.
  echo
  echo -e "${BOLD}Runtime-образы симуляторов${RESET} (не кэш — качаются заново, 4-9 ГБ каждый)"
  sim_runtimes=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && sim_runtimes+=("$line")
  done < <("$SIMCTL" runtime list 2>/dev/null | grep -E ' - [0-9A-Fa-f-]{36} \(')

  # uuid -> размер в байтах (simctl отдаёт sizeBytes только в JSON)
  sim_sizes=$("$SIMCTL" runtime list -j 2>/dev/null | awk '
    /^  "/ && /" : \{$/ { uuid=$1; gsub(/"/, "", uuid); next }
    /"sizeBytes"/ && uuid != "" { bytes=$0; gsub(/[^0-9]/, "", bytes); print uuid, bytes }
  ')

  if (( ${#sim_runtimes[@]} == 0 )); then
    echo -e "  Установленных runtime не найдено."
  else
    for line in "${sim_runtimes[@]}"; do
      name=${line%% - *}
      rest=${line#* - }
      uuid=${rest%% *}
      bytes=$(printf '%s\n' "$sim_sizes" | awk -v u="$uuid" '$1 == u {print $2}')
      echo
      echo -e "  ${BOLD}${name}${RESET} — ${RED}$(human_size "${bytes:-0}")${RESET}"
      if ask "    Удалить?"; then
        if "$SIMCTL" runtime delete "$uuid" 2>/dev/null; then
          total_freed=$((total_freed + ${bytes:-0} / 1024))
          echo -e "    ${GREEN}Готово.${RESET}"
        else
          echo -e "    ${RED}Не удалось удалить (возможно, runtime используется).${RESET}"
        fi
      else
        echo -e "    Пропуск."
      fi
    done
  fi
fi

# Android
echo
echo -e "${BOLD}--- Android ---${RESET}"
clean_step "Android SDK/AVD" "$HOME/Library/Android"
clean_step "Android кэш" "$HOME/.android/cache"

# Кэши сборки
# ВНИМАНИЕ (спорные): содержимое ниже не «мусор», а кэши пакетов —
# после очистки всё перекачивается заново при следующей установке/сборке.
echo
echo -e "${BOLD}--- Кэши сборки (перекачиваются заново) ---${RESET}"
clean_step "Gradle" "$HOME/.gradle/caches"
clean_step "Cargo (registry)" "$HOME/.cargo/registry"
clean_step "Go modules" "$HOME/go/pkg/mod/cache"
clean_step "npm" "$HOME/.npm"
clean_step "pnpm" "$HOME/Library/pnpm/store"
clean_step "Yarn" "$HOME/Library/Caches/Yarn"
clean_step "Bun" "$HOME/.bun/install/cache"
clean_step "Deno" "$HOME/Library/Caches/deno"
clean_step "CocoaPods" "$HOME/Library/Caches/CocoaPods"
clean_step "pip" "$HOME/Library/Caches/pip"
clean_step "uv" "$HOME/.cache/uv"
clean_step "Maven (.m2)" "$HOME/.m2/repository"
clean_step "Composer" "$HOME/Library/Caches/composer"
clean_step "HuggingFace" "$HOME/.cache/huggingface"

# Кэши приложений (Electron)
echo
echo -e "${BOLD}--- Кэши приложений ---${RESET}"
clean_step "VS Code Cache" "$HOME/Library/Application Support/Code/Cache"
clean_step "VS Code CachedData" "$HOME/Library/Application Support/Code/CachedData"
clean_step "Slack" "$HOME/Library/Application Support/Slack/Cache"
clean_step "Discord" "$HOME/Library/Application Support/discord/Cache"

# Системная диагностика и отчёты
echo
echo -e "${BOLD}--- Диагностика и отчёты ---${RESET}"
clean_step "DiagnosticReports" "$HOME/Library/Logs/DiagnosticReports"
clean_step "CrashReporter" "$HOME/Library/Application Support/CrashReporter"
clean_step "Saved Application State" "$HOME/Library/Saved Application State"

# Docker
echo
if command -v docker &>/dev/null; then
  echo -e "${BOLD}Docker — неиспользуемые данные${RESET}"
  if ask "  Запустить docker system prune?"; then
    prune_out=$(docker system prune -f 2>/dev/null || true)
    reclaimed=$(printf '%s\n' "$prune_out" | awk '/reclaimed/ {print $NF}')
    if [[ -n "$reclaimed" ]]; then
      # Docker пишет "Total reclaimed space: 1.077GB" — переводим в КБ для total_freed
      reclaimed_kb=$(printf '%s\n' "$reclaimed" | awk '{
        v=$1; sub(/[a-zA-Z]+$/, "", v)
        u=$1; sub(/^[0-9.]+/, "", u)
        if (u == "GB") m = 1048576; else if (u == "MB") m = 1024; else if (u == "kB") m = 1; else m = 0
        printf "%.0f", v * m
      }')
      total_freed=$((total_freed + reclaimed_kb))
      echo -e "  Освобождено Docker: ${reclaimed}"
    fi
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

# Системные утилиты macOS (не папки — пересборка кэшей и снапшотов)
echo
echo -e "${BOLD}--- Системные кэши и снапшоты ---${RESET}"

if ask "Сбросить кэш превью QuickLook?"; then
  qlmanage -r cache &>/dev/null || true
  echo -e "  ${GREEN}Готово.${RESET}"
fi

if ask "Сбросить кэш шрифтов (нужен sudo)?"; then
  sudo atsutil databases -remove &>/dev/null || true
  atsutil server -shutdown &>/dev/null || true
  atsutil server -ping &>/dev/null || true
  echo -e "  ${GREEN}Готово (изменения вступят в силу после перезапуска).${RESET}"
fi

if ask "Удалить локальные снапшоты Time Machine (освобождает purgeable-место)?"; then
  for snap in $(tmutil listlocalsnapshotdates / 2>/dev/null | grep -E '^[0-9]'); do
    sudo tmutil deletelocalsnapshots "$snap" &>/dev/null || true
  done
  echo -e "  ${GREEN}Готово.${RESET}"
fi

# Корзины на внешних дисках
echo
if compgen -G "/Volumes/*/.Trashes" >/dev/null 2>&1; then
  echo -e "${BOLD}Корзины внешних дисков${RESET} (/Volumes/*/.Trashes)"
  if ask "  Очистить?"; then
    sudo rm -rf /Volumes/*/.Trashes/* 2>/dev/null || true
    echo -e "  ${GREEN}Готово.${RESET}"
  else
    echo -e "  Пропуск."
  fi
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
  echo -e "Освобождено по шагам: ${GREEN}${freed_mb} МБ${RESET}"
fi
disk_avail_end=$(df -k / | awk 'NR==2 {print $4}')
disk_freed_mb=$(( (disk_avail_end - disk_avail_start) / 1024 ))
if (( disk_freed_mb > 0 )); then
  echo -e "Свободного места на диске стало больше на: ${GREEN}${disk_freed_mb} МБ${RESET}"
fi
echo
