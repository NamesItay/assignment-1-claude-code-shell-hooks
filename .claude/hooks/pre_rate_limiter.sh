#!/bin/bash
# =============================================================================
# Pre-Hook 2: Rate Limiter
# Purpose:    Track command count per session, block after exceeding limit.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},"session_id":"..."}
# Exit codes: 0 = allow (possibly with warning), 2 = blocked (limit exceeded)
# State file: data/.command_count — format per line: session_id|total|type1:N,type2:N,...
# =============================================================================

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/hooks.conf"
DATA_DIR="$HOOK_DIR/data"
STATE_FILE="$DATA_DIR/.command_count"
RESET_FILE="$DATA_DIR/.reset_commands"

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "$INPUT" | grep -o '"tool_name":"[^"]*"' | head -1 | sed 's/"tool_name":"//;s/"//')"
COMMAND="$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')"
SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')"

if [ -n "$TOOL_NAME" ] && [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

[ -z "$SESSION_ID" ] && SESSION_ID="default"

MAX_COMMANDS="$(grep -E '^MAX_COMMANDS=' "$CONFIG_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2)"
WARNING_THRESHOLD="$(grep -E '^WARNING_THRESHOLD=' "$CONFIG_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2)"

case "$MAX_COMMANDS" in
    ''|*[!0-9]*) MAX_COMMANDS=50 ;;
esac

case "$WARNING_THRESHOLD" in
    ''|*[!0-9]*) WARNING_THRESHOLD=40 ;;
esac

mkdir -p "$DATA_DIR"
[ -f "$STATE_FILE" ] || : > "$STATE_FILE"

if [ -f "$RESET_FILE" ]; then
    TEMP_STATE="$(mktemp)"
    awk -F'|' -v sid="$SESSION_ID" '$1 != sid' "$STATE_FILE" > "$TEMP_STATE"
    mv "$TEMP_STATE" "$STATE_FILE"
    rm -f "$RESET_FILE"
fi

SESSION_LINE="$(awk -F'|' -v sid="$SESSION_ID" '$1 == sid {print; exit}' "$STATE_FILE" 2>/dev/null)"

TOTAL_COUNT=0
BREAKDOWN=""

if [ -n "$SESSION_LINE" ]; then
    TOTAL_COUNT="$(printf '%s' "$SESSION_LINE" | cut -d'|' -f2)"
    BREAKDOWN="$(printf '%s' "$SESSION_LINE" | cut -d'|' -f3-)"
fi

case "$TOTAL_COUNT" in
    ''|*[!0-9]*) TOTAL_COUNT=0 ;;
esac

TOTAL_COUNT=$((TOTAL_COUNT + 1))

COMMAND_TYPE="$(printf '%s\n' "$COMMAND" | awk '{print $1}')"
[ -z "$COMMAND_TYPE" ] && COMMAND_TYPE="unknown"

NEW_BREAKDOWN=""
FOUND_TYPE=0

if [ -n "$BREAKDOWN" ]; then
    OLD_IFS="$IFS"
    IFS=','
    read -r -a ENTRIES <<< "$BREAKDOWN"
    IFS="$OLD_IFS"

    for entry in "${ENTRIES[@]}"; do
        [ -z "$entry" ] && continue

        TYPE_NAME="${entry%%:*}"
        TYPE_COUNT="${entry#*:}"

        case "$TYPE_COUNT" in
            ''|*[!0-9]*) TYPE_COUNT=0 ;;
        esac

        if [ "$TYPE_NAME" = "$COMMAND_TYPE" ]; then
            TYPE_COUNT=$((TYPE_COUNT + 1))
            FOUND_TYPE=1
        fi

        if [ -n "$NEW_BREAKDOWN" ]; then
            NEW_BREAKDOWN="$NEW_BREAKDOWN,$TYPE_NAME:$TYPE_COUNT"
        else
            NEW_BREAKDOWN="$TYPE_NAME:$TYPE_COUNT"
        fi
    done
fi

if [ "$FOUND_TYPE" -eq 0 ]; then
    if [ -n "$NEW_BREAKDOWN" ]; then
        NEW_BREAKDOWN="$NEW_BREAKDOWN,$COMMAND_TYPE:1"
    else
        NEW_BREAKDOWN="$COMMAND_TYPE:1"
    fi
fi

TEMP_STATE="$(mktemp)"
awk -F'|' -v sid="$SESSION_ID" '$1 != sid' "$STATE_FILE" > "$TEMP_STATE"
printf '%s|%s|%s\n' "$SESSION_ID" "$TOTAL_COUNT" "$NEW_BREAKDOWN" >> "$TEMP_STATE"
mv "$TEMP_STATE" "$STATE_FILE"

if [ "$TOTAL_COUNT" -gt "$MAX_COMMANDS" ]; then
    printf "BLOCKED: Session '%s' exceeded command limit (%d > %d). Breakdown: %s\n" \
        "$SESSION_ID" "$TOTAL_COUNT" "$MAX_COMMANDS" "$NEW_BREAKDOWN" >&2
    exit 2
fi

if [ "$TOTAL_COUNT" -gt "$WARNING_THRESHOLD" ]; then
    printf "WARNING: Session '%s' is approaching the command limit (%d/%d). Breakdown: %s\n" \
        "$SESSION_ID" "$TOTAL_COUNT" "$MAX_COMMANDS" "$NEW_BREAKDOWN" >&2
    exit 0
fi

exit 0
