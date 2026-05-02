#!/bin/bash
# =============================================================================
# Post-Hook 6: Session Summary
# Purpose:    Generate a formatted summary from session.log when Claude stops.
# Input:      JSON on stdin: {"session_id":"...","cwd":"...","stop_hook_active":false}
# Exit codes: 0 always
# IMPORTANT:  Checks stop_hook_active first to prevent infinite loops.
# =============================================================================

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$HOOK_DIR/data"
INPUT="$(cat)"

extract_json_string() {
    local json="$1"
    local key="$2"
    local marker rest value ch next

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

extract_json_boolean() {
    local json="$1"
    local key="$2"
    local marker rest

    marker="\"$key\":"
    case "$json" in
        *"$marker"*)
            rest="${json#*${marker}}"
            ;;
        *)
            return 1
            ;;
    esac

    case "$rest" in
        true* ) printf 'true'; return 0 ;;
        false* ) printf 'false'; return 0 ;;
    esac

    return 1
}

STOP_HOOK_ACTIVE="$(extract_json_boolean "$INPUT" "stop_hook_active")"
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

SESSION_ID="$(extract_json_string "$INPUT" "session_id")"
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="default"
fi

LOG_FILE="$DATA_DIR/session_${SESSION_ID}.log"

if [ ! -s "$LOG_FILE" ]; then
    printf 'No session activity recorded.\n'
    exit 0
fi

TOTAL_ACTIONS="$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d '[:space:]')"
BACKUPS_MADE="$(grep -c ' BACKUP ' "$LOG_FILE" 2>/dev/null)"
SYNTAX_OK_COUNT="$(grep -c ' SYNTAX_OK ' "$LOG_FILE" 2>/dev/null)"
SYNTAX_ERROR_COUNT="$(grep -c ' SYNTAX_ERROR ' "$LOG_FILE" 2>/dev/null)"
SYNTAX_CHECKS=$((SYNTAX_OK_COUNT + SYNTAX_ERROR_COUNT))

FIRST_TIMESTAMP="$(sed -n '1s/^\[\([^]]*\)\].*/\1/p' "$LOG_FILE")"
LAST_TIMESTAMP="$(sed -n '$s/^\[\([^]]*\)\].*/\1/p' "$LOG_FILE")"

TOP_FILES="$(awk '
/ BACKUP / {
    start = index($0, " BACKUP ")
    end = index($0, " -> ")
    if (start > 0 && end > start) {
        file = substr($0, start + 8, end - (start + 8))
        count[file]++
    }
}
END {
    for (file in count) {
        printf "%d\t%s\n", count[file], file
    }
}
' "$LOG_FILE" | sort -rn -k1,1 -k2,2 | head -3)"

FILE_TYPE_COUNTS="$(awk '
/ BACKUP / {
    start = index($0, " BACKUP ")
    end = index($0, " -> ")
    if (start > 0 && end > start) {
        file = substr($0, start + 8, end - (start + 8))
        ext = file
        sub(/^.*\./, "", ext)
        if (ext == file || ext == "") {
            ext = "noext"
        }
        count[ext]++
    }
}
END {
    for (ext in count) {
        printf "%s\t%d\n", ext, count[ext]
    }
}
' "$LOG_FILE" | sort -k1,1)"

printf '╔══════════════════════════════════════╗\n'
printf '║        SESSION SUMMARY REPORT        ║\n'
printf '╚══════════════════════════════════════╝\n'
printf '\n'
printf 'Session: %s\n' "$SESSION_ID"
printf 'Period:  %s -> %s\n' "$FIRST_TIMESTAMP" "$LAST_TIMESTAMP"
printf '\n'
printf '── Activity ─────────────────────────\n'
printf '  Total actions:  %s\n' "$TOTAL_ACTIONS"
printf '  Backups made:   %s\n' "$BACKUPS_MADE"
printf '  Syntax checks:  %s\n' "$SYNTAX_CHECKS"
printf '  Syntax errors:  %s\n' "$SYNTAX_ERROR_COUNT"
printf '\n'
printf '── Most Edited Files ────────────────\n'

if [ -n "$TOP_FILES" ]; then
    INDEX=1
    while IFS=$'\t' read -r count file; do
        [ -z "$file" ] && continue
        printf '  %d. %-24s (%s edits)\n' "$INDEX" "$file" "$count"
        INDEX=$((INDEX + 1))
    done <<EOF_TOP
$TOP_FILES
EOF_TOP
else
    printf '  No edited files recorded.\n'
fi

printf '\n'
printf '── File Types ───────────────────────\n'
if [ -n "$FILE_TYPE_COUNTS" ]; then
    while IFS=$'\t' read -r ext count; do
        [ -z "$ext" ] && continue
        if [ "$ext" = "noext" ]; then
            printf '  %-8s files: %s\n' '[noext]' "$count"
        else
            printf '  .%-7s files: %s\n' "$ext" "$count"
        fi
    done <<EOF_TYPES
$FILE_TYPE_COUNTS
EOF_TYPES
else
    printf '  No file type data recorded.\n'
fi

exit 0
