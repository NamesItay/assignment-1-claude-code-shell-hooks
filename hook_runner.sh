#!/bin/bash
# =============================================================================
# Hook Runner
# Purpose:    Standalone simulator of Claude Code's hook execution for testing.
#             Reads hooks_config.txt, matches event+tool, runs hooks in order.
# Usage:      echo '<json>' | ./hook_runner.sh <event_type> <tool_name>
# Examples:
#   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"s1"}' \
#       | ./hook_runner.sh PreToolUse Bash
#   echo '{"tool_name":"Edit","tool_input":{"file_path":"main.c"},"session_id":"s1"}' \
#       | ./hook_runner.sh PostToolUse Edit
# =============================================================================

# ── Colour codes ───────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$RUNNER_DIR/hooks_config.txt"

# ── Argument validation ────────────────────────────────────────────────────────
if [ -z "$1" ] || [ -z "$2" ]; then
    printf '%bUsage:%b echo '\''<json>'\'' | %s <event_type> <tool_name>\n' "$BOLD" "$RESET" "$0"
    printf '\n'
    printf 'event_type examples: PreToolUse, PostToolUse, Stop\n'
    printf 'tool_name  examples: Bash, Edit, Write, MultiEdit, *\n'
    printf '\n'
    printf 'Config file: %s\n' "$CONFIG_FILE"
    exit 1
fi

EVENT_TYPE="$1"
TOOL_NAME="$2"

# ── Validate config file ───────────────────────────────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    printf '%bERROR:%b Config file not found: %s\n' "$RED" "$RESET" "$CONFIG_FILE" >&2
    exit 1
fi

# ── Read stdin into temp file (hooks need to re-read it) ──────────────────────
TEMP_FILE="$(mktemp)"
trap 'rm -f "$TEMP_FILE"' EXIT
cat > "$TEMP_FILE"

printf '%b─── Hook Runner (%s / %s) ───%b\n' "$BOLD" "$EVENT_TYPE" "$TOOL_NAME" "$RESET"
printf '\n'

# ── Statistics ────────────────────────────────────────────────────────────────
MATCHED=0
PASSED=0
BLOCKED=0
WARNINGS=0
FINAL_EXIT=0

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ''|'#'*) continue ;;
    esac

    CONF_EVENT="${line%%:*}"
    remainder="${line#*:}"

    if [ "$remainder" = "$line" ]; then
        continue
    fi

    CONF_MATCHER="${remainder%%:*}"
    CONF_SCRIPT="${remainder#*:}"

    if [ "$CONF_SCRIPT" = "$remainder" ]; then
        continue
    fi

    [ "$CONF_EVENT" = "$EVENT_TYPE" ] || continue
    if [ "$CONF_MATCHER" != '*' ] && [ "$CONF_MATCHER" != "$TOOL_NAME" ]; then
        continue
    fi

    MATCHED=$((MATCHED + 1))

    case "$CONF_SCRIPT" in
        ./*) SCRIPT_PATH="$RUNNER_DIR/${CONF_SCRIPT#./}" ;;
        *) SCRIPT_PATH="$CONF_SCRIPT" ;;
    esac

    printf '%b▶ Running:%b %s\n' "$CYAN" "$RESET" "$CONF_SCRIPT"

    STDERR_FILE="$(mktemp)"
    if [ -x "$SCRIPT_PATH" ]; then
        bash "$SCRIPT_PATH" < "$TEMP_FILE" > /dev/null 2> "$STDERR_FILE"
    else
        bash "$SCRIPT_PATH" < "$TEMP_FILE" > /dev/null 2> "$STDERR_FILE"
    fi
    EXIT_CODE=$?

    case "$EXIT_CODE" in
        0)
            printf '  %b✓ Passed%b\n' "$GREEN" "$RESET"
            PASSED=$((PASSED + 1))
            ;;
        2)
            printf '  %b✗ BLOCKED%b\n' "$RED" "$RESET"
            if [ -s "$STDERR_FILE" ]; then
                while IFS= read -r err_line || [ -n "$err_line" ]; do
                    printf '  %s\n' "$err_line"
                done < "$STDERR_FILE"
            fi
            BLOCKED=$((BLOCKED + 1))
            FINAL_EXIT=2
            rm -f "$STDERR_FILE"
            printf '[Chain stopped — hook returned exit 2]\n'
            printf '\n'
            break
            ;;
        *)
            printf '  %b⚠ Warning (exit %s)%b\n' "$YELLOW" "$EXIT_CODE" "$RESET"
            if [ -s "$STDERR_FILE" ]; then
                while IFS= read -r err_line || [ -n "$err_line" ]; do
                    printf '  %s\n' "$err_line"
                done < "$STDERR_FILE"
            fi
            WARNINGS=$((WARNINGS + 1))
            ;;
    esac

    rm -f "$STDERR_FILE"
    printf '\n'
done < "$CONFIG_FILE"

# ── Summary ────────────────────────────────────────────────────────────────────
printf '%b─── Hook Execution Summary ──────────%b\n' "$BOLD" "$RESET"
printf 'Matched:  %d hooks\n' "$MATCHED"
printf '%bPassed:   %d%b\n' "$GREEN" "$PASSED" "$RESET"
if [ "$BLOCKED" -gt 0 ]; then
    printf '%bBlocked:  %d%b\n' "$RED" "$BLOCKED" "$RESET"
else
    printf 'Blocked:  %d\n' "$BLOCKED"
fi
if [ "$WARNINGS" -gt 0 ]; then
    printf '%bWarnings: %d%b\n' "$YELLOW" "$WARNINGS" "$RESET"
else
    printf 'Warnings: %d\n' "$WARNINGS"
fi

exit $FINAL_EXIT
