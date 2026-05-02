#!/bin/bash
# =============================================================================
# Pre-Hook 3: Commit Message Validator
# Purpose:    Validate git commit messages follow conventional commit format.
#             Suggests a prefix if one is missing based on staged diff heuristics.
# Input:      JSON on stdin: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Exit codes: 0 = allow, 2 = block (invalid commit message)
# =============================================================================

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOOK_DIR/config/commit_prefixes.txt"

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

extract_commit_message() {
    local cmd=" $1"
    local msg

    msg="$(printf '%s' "$cmd" | sed -n "s/.*[[:space:]]-am[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)"
    [ -n "$msg" ] && { printf '%s' "$msg"; return 0; }

    msg="$(printf '%s' "$cmd" | sed -n 's/.*[[:space:]]-am[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$msg" ] && { printf '%s' "$msg"; return 0; }

    msg="$(printf '%s' "$cmd" | sed -n "s/.*[[:space:]]-a[[:space:]][[:space:]]*-m[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)"
    [ -n "$msg" ] && { printf '%s' "$msg"; return 0; }

    msg="$(printf '%s' "$cmd" | sed -n 's/.*[[:space:]]-a[[:space:]][[:space:]]*-m[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$msg" ] && { printf '%s' "$msg"; return 0; }

    msg="$(printf '%s' "$cmd" | sed -n "s/.*[[:space:]]-m[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)"
    [ -n "$msg" ] && { printf '%s' "$msg"; return 0; }

    msg="$(printf '%s' "$cmd" | sed -n 's/.*[[:space:]]-m[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$msg" ] && { printf '%s' "$msg"; return 0; }

    return 1
}

load_prefixes() {
    local line first=1 joined=""

    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r line; do
            case "$line" in
                ''|'#'*) continue ;;
            esac
            if [ "$first" -eq 1 ]; then
                joined="$line"
                first=0
            else
                joined="$joined|$line"
            fi
        done < "$CONFIG_FILE"
    fi

    if [ -z "$joined" ]; then
        joined='feat|fix|docs|refactor|test|chore'
    fi

    printf '%s' "$joined"
}

suggest_prefix() {
    local cwd="$1"
    local stat_output=""
    local name_status=""
    local insertions deletions

    if [ -n "$cwd" ] && [ -d "$cwd" ]; then
        stat_output="$(git -C "$cwd" diff --cached --stat 2>/dev/null)"
        name_status="$(git -C "$cwd" diff --cached --name-status 2>/dev/null)"
    else
        stat_output="$(git diff --cached --stat 2>/dev/null)"
        name_status="$(git diff --cached --name-status 2>/dev/null)"
    fi

    if printf '%s\n%s\n' "$name_status" "$stat_output" | grep -qiE 'test|spec'; then
        printf 'test'
        return 0
    fi

    if printf '%s\n%s\n' "$name_status" "$stat_output" | grep -qiE 'README|\.md'; then
        printf 'docs'
        return 0
    fi

    if printf '%s' "$name_status" | grep -qE '^A[[:space:]]'; then
        printf 'feat'
        return 0
    fi

    insertions="$(printf '%s' "$stat_output" | grep -oE '[0-9]+ insertion[s]?\(\+\)' | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')"
    deletions="$(printf '%s' "$stat_output" | grep -oE '[0-9]+ deletion[s]?\(-\)' | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')"

    if [ "$deletions" -gt "$insertions" ]; then
        printf 'refactor'
        return 0
    fi

    printf 'feat'
}

TOOL_NAME="$(extract_json_string "$INPUT" "tool_name")"
COMMAND="$(extract_json_string "$INPUT" "command")"
SESSION_CWD="$(extract_json_string "$INPUT" "cwd")"

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

if ! printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]])git[[:space:]]+commit([[:space:]]|$)'; then
    exit 0
fi

if ! printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]])-m([[:space:]]|$)|(^|[[:space:]])-am([[:space:]]|$)'; then
    exit 0
fi

COMMIT_MSG="$(extract_commit_message "$COMMAND")"
if [ -z "$COMMIT_MSG" ]; then
    exit 0
fi

PREFIX_REGEX="$(load_prefixes)"
VALID_PREFIXES="$(printf '%s' "$PREFIX_REGEX" | tr '|' ',' | sed 's/,/, /g')"

if ! printf '%s' "$COMMIT_MSG" | grep -qE "^($PREFIX_REGEX): "; then
    SUGGESTED_PREFIX="$(suggest_prefix "$SESSION_CWD")"
    printf "BLOCKED: Missing commit prefix. Based on your changes, try: '%s: %s'. Valid prefixes: %s\n" \
        "$SUGGESTED_PREFIX" "$COMMIT_MSG" "$VALID_PREFIXES" >&2
    exit 2
fi

MSG_LENGTH=${#COMMIT_MSG}
if [ "$MSG_LENGTH" -lt 10 ] || [ "$MSG_LENGTH" -gt 72 ]; then
    printf 'BLOCKED: Commit message must be 10-72 characters long (got %d).\n' "$MSG_LENGTH" >&2
    exit 2
fi

case "$COMMIT_MSG" in
    *.)
        printf 'BLOCKED: Commit message must not end with a period.\n' >&2
        exit 2
        ;;
esac

exit 0
