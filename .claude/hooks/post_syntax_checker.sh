#!/bin/bash
# =============================================================================
# Post-Hook 5: Syntax Checker
# Purpose:    Run appropriate syntax checker based on file extension after edit.
# Input:      JSON on stdin: {"tool_name":"Edit","tool_input":{"file_path":"..."},...}
# Exit codes: 0 = syntax OK (or no checker), 1 = syntax error (warn, don't block)
# Supported:  .sh/.bash (bash -n), .py (python3 -m py_compile), .c/.h (gcc -fsyntax-only)
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

FILE_PATH="$(extract_json_string "$INPUT" "file_path")"
SESSION_ID="$(extract_json_string "$INPUT" "session_id")"

if [ -z "$SESSION_ID" ]; then
    SESSION_ID="default"
fi

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

mkdir -p "$DATA_DIR" 2>/dev/null || true
LOG_FILE="$DATA_DIR/session_${SESSION_ID}.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
EXTENSION="${FILE_PATH##*.}"
CHECK_OUTPUT=""
CHECK_STATUS=0

run_checker() {
    case "$EXTENSION" in
        sh|bash)
            CHECK_OUTPUT="$(bash -n "$FILE_PATH" 2>&1)"
            CHECK_STATUS=$?
            ;;
        py)
            CHECK_OUTPUT="$(python3 -m py_compile "$FILE_PATH" 2>&1)"
            CHECK_STATUS=$?
            ;;
        c|h)
            CHECK_OUTPUT="$(gcc -fsyntax-only "$FILE_PATH" 2>&1)"
            CHECK_STATUS=$?
            ;;
        *)
            printf 'No syntax checker for .%s\n' "$EXTENSION" >&2
            exit 0
            ;;
    esac
}

run_checker

if [ "$CHECK_STATUS" -ne 0 ]; then
    printf 'SYNTAX ERROR in %s:\n' "$FILE_PATH" >&2
    if [ -n "$CHECK_OUTPUT" ]; then
        printf '%s\n' "$CHECK_OUTPUT" >&2
    fi
    printf '[%s] SYNTAX_ERROR %s (%s)\n' "$TIMESTAMP" "$FILE_PATH" "$EXTENSION" >> "$LOG_FILE"
    exit 1
fi

printf 'Syntax OK: %s\n' "$FILE_PATH"
printf '[%s] SYNTAX_OK %s (%s)\n' "$TIMESTAMP" "$FILE_PATH" "$EXTENSION" >> "$LOG_FILE"
exit 0
