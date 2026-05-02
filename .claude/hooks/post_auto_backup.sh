#!/bin/bash
# =============================================================================
# Post-Hook 4: Auto-Backup
# Purpose:    After a file edit, create a timestamped backup with rotation.
# Input:      JSON on stdin: {"tool_name":"Edit","tool_input":{"file_path":"..."},...}
# Exit codes: 0 always (post-hooks should not block)
# Backups:    data/.backups/<basename>.<timestamp>
# Log:        data/session_<session_id>.log
# =============================================================================

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"
DATA_DIR="$HOOK_DIR/data"
BACKUP_DIR="$DATA_DIR/.backups"

INPUT="$(cat)"

extract_json_string() {
    local json="$1"
    local key="$2"
    local marker value rest ch next

    marker="\"$key\":\""
    case "$json" in
        *"$marker"*)
            rest="${json#*${marker}}"
            ;;
        *)
            return 1
            ;;
    esac

    value=""
    while [ -n "$rest" ]; do
        ch="${rest%${rest#?}}"
        rest="${rest#?}"

        if [ "$ch" = '\\' ]; then
            if [ -z "$rest" ]; then
                value="$value\\"
                break
            fi
            next="${rest%${rest#?}}"
            rest="${rest#?}"
            case "$next" in
                '"'|'\\'|'/') value="$value$next" ;;
                'n') value="$value"
                     value="$value
" ;;
                'r') value="$value"
                     value="$value" ;;
                't') value="$value	" ;;
                *) value="$value\\$next" ;;
            esac
            continue
        fi

        if [ "$ch" = '"' ]; then
            printf '%s' "$value"
            return 0
        fi

        value="$value$ch"
    done

    return 1
}

read_config_value() {
    local key="$1"
    local default_value="$2"
    local value=""

    if [ "$key" = 'MAX_BACKUPS' ] && [ -n "$MAX_BACKUPS" ]; then
        printf '%s' "$MAX_BACKUPS"
        return 0
    fi

    if [ -f "$CONFIG_FILE" ]; then
        value="$(grep -E "^[[:space:]]*$key=" "$CONFIG_FILE" | tail -1 | cut -d'=' -f2-)"
    fi

    if [ -z "$value" ]; then
        value="$default_value"
    fi

    printf '%s' "$value"
}

FILE_PATH="$(extract_json_string "$INPUT" "file_path")"
SESSION_ID="$(extract_json_string "$INPUT" "session_id")"

if [ -z "$SESSION_ID" ]; then
    SESSION_ID="default"
fi

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

mkdir -p "$BACKUP_DIR" 2>/dev/null || exit 0

TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
BASENAME="$(basename "$FILE_PATH")"
BACKUP_NAME="$BASENAME.$TIMESTAMP"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
RELATIVE_BACKUP_PATH=".backups/$BACKUP_NAME"
LOG_FILE="$DATA_DIR/session_${SESSION_ID}.log"

cp -- "$FILE_PATH" "$BACKUP_PATH" 2>/dev/null || exit 0

FILE_SIZE="$(wc -c < "$FILE_PATH" 2>/dev/null | tr -d '[:space:]')"
LOG_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
printf '[%s] BACKUP %s -> %s (%s bytes)\n' \
    "$LOG_TIMESTAMP" "$FILE_PATH" "$RELATIVE_BACKUP_PATH" "$FILE_SIZE" >> "$LOG_FILE"

MAX_BACKUPS_VALUE="$(read_config_value "MAX_BACKUPS" "5")"
case "$MAX_BACKUPS_VALUE" in
    ''|*[!0-9]*) MAX_BACKUPS_VALUE=5 ;;
esac

shopt -s nullglob
BACKUP_FILES=( "$BACKUP_DIR"/"$BASENAME".* )
shopt -u nullglob

if [ "${#BACKUP_FILES[@]}" -gt "$MAX_BACKUPS_VALUE" ]; then
    IFS=$'\n' SORTED_BACKUPS=( $(ls -1t "${BACKUP_FILES[@]}" 2>/dev/null) )
    unset IFS

    INDEX="$MAX_BACKUPS_VALUE"
    while [ "$INDEX" -lt "${#SORTED_BACKUPS[@]}" ]; do
        rm -f -- "${SORTED_BACKUPS[$INDEX]}"
        INDEX=$((INDEX + 1))
    done
fi

exit 0
