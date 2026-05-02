#!/bin/bash
# =============================================================================
# Pre-Hook 1: Command Firewall
# Purpose:    Block dangerous bash commands before execution.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (dangerous pattern matched)
# =============================================================================

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/dangerous_patterns.txt"

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "$INPUT" \
    | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

COMMAND="$(printf '%s' "$INPUT" \
    | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

if [ -z "$COMMAND" ]; then
    exit 0
fi

if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

while IFS= read -r line; do
    line="${line%$'\r'}"
    PATTERN="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    case "$PATTERN" in
        ''|'#'*)
            continue
            ;;
    esac

    if printf '%s\n' "$COMMAND" | grep -qE -- "$PATTERN"; then
        printf "BLOCKED: Command matches dangerous pattern '%s'. Please use a safer alternative.\n" "$PATTERN" >&2
        exit 2
    fi
done < "$CONFIG_FILE"

exit 0
