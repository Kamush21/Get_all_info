#!/usr/bin/env bash

# Название: get_all_info.sh
# Назначение: сбор основной информации о Linux-системе
# Поддерживаемые системы: Debian, Ubuntu и их производные

set -Eeuo pipefail
umask 077

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPORT="${SCRIPT_DIR}/info"
readonly ARCHIVE="${SCRIPT_DIR}/OS_RESULT.tar"
readonly REQUIRED_PACKAGES=(cowsay sl)

# Вывод информационных сообщений с датой и временем
log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

# Вывод сообщения об ошибке и завершение работы
die() {
    log "ОШИБКА: $*"
    exit 1
}

# 1. Проверяем, запущен ли скрипт от имени root
if (( EUID != 0 )); then
    die "Запустите скрипт от имени root: sudo ./${SCRIPT_NAME}"
fi

# 2. Проверяем наличие файла с информацией об операционной системе
[[ -r /etc/os-release ]] ||
    die "Файл /etc/os-release не найден или недоступен для чтения"

# Проверяем наличие необходимых команд
for cmd in apt-get dpkg-query ps ss uname tar mktemp; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Необходимая команда не найдена: $cmd"
done

# 3. Проверяем, установлены ли необходимые пакеты
missing_packages=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null |
        grep -q '^install ok installed$'; then
        missing_packages+=("$pkg")
    fi
done

# Устанавливаем только отсутствующие пакеты
if ((${#missing_packages[@]} > 0)); then
    log "Обновление списка пакетов APT"
    apt-get update

    log "Установка пакетов: ${missing_packages[*]}"
    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends \
        "${missing_packages[@]}"
else
    log "Все необходимые пакеты уже установлены"
fi

# 4. Создаём временный файл для формирования отчёта
tmp_report="$(mktemp "${SCRIPT_DIR}/.info.XXXXXX")"

# Удаляем временный файл при завершении работы скрипта
trap 'rm -f -- "${tmp_report:-}"' EXIT

# 5. Собираем информацию о системе и записываем её в отчёт
{
    echo "========================================"
    echo "ОТЧЁТ О СОСТОЯНИИ LINUX-СИСТЕМЫ"
    echo "========================================"

    printf 'Дата и время сбора: '
    date --iso-8601=seconds

    printf 'Имя хоста: '
    hostname

    printf 'Скрипт сбора данных: %s\n' "$SCRIPT_NAME"

    echo
    echo "========================================"
    echo "ИНФОРМАЦИЯ ОБ ОПЕРАЦИОННОЙ СИСТЕМЕ"
    echo "========================================"
    cat /etc/os-release

    echo
    echo "========================================"
    echo "ИНФОРМАЦИЯ О ЯДРЕ LINUX"
    echo "========================================"
    uname -a

    echo
    echo "========================================"
    echo "УСТАНОВЛЕННЫЕ ПАКЕТЫ"
    echo "========================================"
    dpkg-query -W \
        -f='${binary:Package}\t${Version}\t${db:Status-Status}\n'

    echo
    echo "========================================"
    echo "ЗАПУЩЕННЫЕ ПРОЦЕССЫ"
    echo "========================================"
    ps auxww

    echo
    echo "========================================"
    echo "ПРОСЛУШИВАЕМЫЕ TCP/UDP-СОКЕТЫ"
    echo "========================================"
    ss -tulpen

    echo
    echo "========================================"
    echo "АКТИВНЫЕ TCP-СОЕДИНЕНИЯ"
    echo "========================================"
    ss -tanp

} > "$tmp_report"

# 6. Ограничиваем доступ к отчёту и сохраняем его
chmod 600 "$tmp_report"
mv -f -- "$tmp_report" "$REPORT"
tmp_report=""

# 7. Создаём TAR-архив с файлом info
tar -cf "${ARCHIVE}.tmp" -C "$SCRIPT_DIR" info

# Ограничиваем доступ к архиву
chmod 600 "${ARCHIVE}.tmp"

# Переименовываем временный архив в итоговый
mv -f -- "${ARCHIVE}.tmp" "$ARCHIVE"

# 8. Проверяем, что архив содержит файл info
tar -tf "$ARCHIVE" | grep -Fxq 'info' ||
    die "Проверка архива не пройдена: файл info отсутствует"

# 9. Сообщаем об успешном завершении
log "Сбор информации успешно завершён"
log "Отчёт:  ${REPORT}"
log "Архив: ${ARCHIVE}"

