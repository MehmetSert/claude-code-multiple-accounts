# claude-accounts.sh - use multiple Claude Code accounts with shared sessions and config.
# Must be sourced (zsh or bash), not executed.
#
# Install:
#   1) Save this file as ~/.claude-accounts.sh
#   2) Add this line to the END of ~/.zshrc or ~/.bashrc:
#        source ~/.claude-accounts.sh
#   3) Open a new terminal and add an account:
#        claude-accounts add claude-work
#
# Docs: https://github.com/MehmetSert/claude-code-multiple-accounts

# ---------------------------------------------------------------------------
# SETTINGS (set any of these before sourcing to override)
# ---------------------------------------------------------------------------

# Main account: its config directory and the file holding its MCP definitions
CLAUDE_MAIN_DIR="${CLAUDE_MAIN_DIR:-$HOME/.claude}"
CLAUDE_MAIN_JSON="${CLAUDE_MAIN_JSON:-$HOME/.claude.json}"

# List of extra accounts, one name per line. Managed by `claude-accounts add/remove`.
# Each name is both the command and the config directory: claude-work -> ~/.claude-work
CLAUDE_ACCOUNTS_FILE="${CLAUDE_ACCOUNTS_FILE:-$HOME/.config/claude-accounts/accounts}"

# Full path of the `claude` binary, if it is not on PATH
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

# Session data: existing content is merged into the main account, then symlinked
CLAUDE_SHARED_DATA=(projects todos session-env file-history)

# Configuration: the main account is the single source, nothing is merged
CLAUDE_SHARED_CONFIG=(skills plugins commands agents settings.json CLAUDE.md)

CLAUDE_ACCOUNTS=()

# ---------------------------------------------------------------------------
# LINKING
# ---------------------------------------------------------------------------

_claude_acc_log() {
  echo "[claude-accounts] $*" >&2
}

_claude_acc_backup() {
  # Moves $1 aside instead of deleting it
  mv "$1" "$1.bak-$(date +%Y%m%d-%H%M%S)"
}

_claude_acc_link_data() {
  # $1: account directory, $2: item name
  local src="$CLAUDE_MAIN_DIR/$2" dst="$1/$2"
  [ -L "$dst" ] && return 0
  mkdir -p "$src"
  if [ -d "$dst" ]; then
    _claude_acc_log "merging $dst into $src"
    if ! rsync -a --update "$dst/" "$src/"; then
      _claude_acc_log "ERROR: could not merge $dst, left untouched"
      return 1
    fi
    _claude_acc_backup "$dst"
  fi
  ln -s "$src" "$dst"
}

_claude_acc_link_config() {
  # $1: account directory, $2: item name
  local src="$CLAUDE_MAIN_DIR/$2" dst="$1/$2"
  [ -L "$dst" ] && return 0
  [ -e "$src" ] || return 0
  if [ -e "$dst" ]; then
    _claude_acc_backup "$dst"
  fi
  ln -s "$src" "$dst"
}

_claude_acc_link() {
  # $1: account directory
  local dir="$1" item
  mkdir -p "$dir" "$CLAUDE_MAIN_DIR"
  for item in "${CLAUDE_SHARED_DATA[@]}"; do
    _claude_acc_link_data "$dir" "$item"
  done
  for item in "${CLAUDE_SHARED_CONFIG[@]}"; do
    _claude_acc_link_config "$dir" "$item"
  done
}

# ---------------------------------------------------------------------------
# MCP
# ---------------------------------------------------------------------------

_claude_acc_sync_mcp() {
  # Copies the main account's user-scope MCP servers into the account's .claude.json.
  # One-way: the main account always wins. Writes only when something differs.
  # Skipped until the account has logged in once (no .claude.json before that).
  local dst="$1/.claude.json" tmp="$1/.claude.json.tmp.$$" want have
  [ -f "$CLAUDE_MAIN_JSON" ] && [ -f "$dst" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    _claude_acc_log "jq not found, MCP sync skipped"
    return 0
  fi
  want="$(jq -cS '.mcpServers // {}' "$CLAUDE_MAIN_JSON" 2>/dev/null)" || return 0
  have="$(jq -cS '.mcpServers // {}' "$dst" 2>/dev/null)" || return 0
  [ "$want" = "$have" ] && return 0
  # The file holds account credentials, so the temp file must not be world-readable
  if (umask 077 && jq --argjson m "$want" '.mcpServers = $m' "$dst" > "$tmp"); then
    mv "$tmp" "$dst"
    _claude_acc_log "MCP servers updated: $dst"
  else
    rm -f "$tmp"
  fi
}

# ---------------------------------------------------------------------------
# ACCOUNT COMMANDS
# ---------------------------------------------------------------------------

_claude_acc_run() {
  # $1: account name, the rest is passed to claude
  local dir="$HOME/.$1"
  shift
  _claude_acc_link "$dir"
  _claude_acc_sync_mcp "$dir"
  CLAUDE_CONFIG_DIR="$dir" command "$CLAUDE_BIN" "$@"
}

_claude_acc_is_valid_name() {
  case "$1" in
    '' | -* | *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

_claude_acc_define() {
  # Defines a shell function named after the account. Callers validate the name first.
  unalias "$1" 2>/dev/null
  eval "function $1 { _claude_acc_run $1 \"\$@\"; }"
}

_claude_acc_load() {
  # Reads the accounts file and defines a command for each account
  local line
  CLAUDE_ACCOUNTS=()
  [ -f "$CLAUDE_ACCOUNTS_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '' | '#'*) continue ;;
    esac
    if ! _claude_acc_is_valid_name "$line"; then
      _claude_acc_log "ignoring invalid account name in $CLAUDE_ACCOUNTS_FILE: $line"
      continue
    fi
    CLAUDE_ACCOUNTS+=("$line")
    _claude_acc_define "$line"
  done < "$CLAUDE_ACCOUNTS_FILE"
}

_claude_acc_has() {
  [ -n "$1" ] && grep -qxF -- "$1" "$CLAUDE_ACCOUNTS_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

_claude_acc_check_new_name() {
  if ! _claude_acc_is_valid_name "$1"; then
    _claude_acc_log "invalid name '$1': use letters, digits, '-' and '_'"
    return 1
  fi
  if [ "$1" = "claude" ] || [ "$1" = "claude-accounts" ]; then
    _claude_acc_log "'$1' is reserved"
    return 1
  fi
  case "$(command -v "$1" 2>/dev/null)" in
    /*)
      _claude_acc_log "'$1' is already a program on your PATH, pick another name"
      return 1
      ;;
  esac
}

_claude_acc_add() {
  local name="$1" dir="$HOME/.$1"
  _claude_acc_check_new_name "$name" || return 1
  if _claude_acc_has "$name"; then
    _claude_acc_log "$name is already in the list"
    return 0
  fi
  mkdir -p "$(dirname "$CLAUDE_ACCOUNTS_FILE")"
  printf '%s\n' "$name" >> "$CLAUDE_ACCOUNTS_FILE"
  _claude_acc_define "$name"
  _claude_acc_link "$dir"
  _claude_acc_sync_mcp "$dir"
  echo "Added $name ($dir)."
  if [ ! -f "$dir/.claude.json" ]; then
    echo "Run '$name' and log in once with /login."
  fi
}

_claude_acc_remove() {
  local name="$1" tmp="$CLAUDE_ACCOUNTS_FILE.tmp.$$"
  if ! _claude_acc_has "$name"; then
    _claude_acc_log "'$name' is not in the list"
    return 1
  fi
  # grep exits non-zero when the last account is removed; the empty file is correct
  grep -vxF -- "$name" "$CLAUDE_ACCOUNTS_FILE" > "$tmp"
  mv "$tmp" "$CLAUDE_ACCOUNTS_FILE"
  unset -f "$name"
  echo "Removed $name. Its directory $HOME/.$name was kept."
}

_claude_acc_item_state() {
  # $1: account directory, $2: item name
  if [ -L "$1/$2" ]; then
    echo "linked"
  elif [ -e "$CLAUDE_MAIN_DIR/$2" ]; then
    echo "NOT LINKED"
  else
    echo "skipped (not in main account)"
  fi
}

_claude_acc_list() {
  local name dir item
  if [ "${#CLAUDE_ACCOUNTS[@]}" -eq 0 ]; then
    echo "No accounts yet. Add one with: claude-accounts add <name>"
    return 0
  fi
  for name in "${CLAUDE_ACCOUNTS[@]}"; do
    dir="$HOME/.$name"
    echo "$name  ($dir)"
    for item in "${CLAUDE_SHARED_DATA[@]}" "${CLAUDE_SHARED_CONFIG[@]}"; do
      printf '  %-14s %s\n' "$item" "$(_claude_acc_item_state "$dir" "$item")"
    done
  done
}

_claude_acc_sync() {
  local name
  for name in "${CLAUDE_ACCOUNTS[@]}"; do
    _claude_acc_link "$HOME/.$name"
    _claude_acc_sync_mcp "$HOME/.$name"
  done
  _claude_acc_list
}

_claude_acc_help() {
  cat <<'EOF'
Usage: claude-accounts <command>

  add <name>      Add an account. <name> becomes a command and uses ~/.<name>
  remove <name>   Remove an account from the list (its directory is kept)
  list            Show accounts and what is linked
  sync            Repair links and copy MCP servers for all accounts
  help            Show this help

Start a session with the account name, e.g.:  claude-work -c
EOF
}

claude-accounts() {
  local cmd="${1:-help}"
  [ $# -gt 0 ] && shift
  _claude_acc_load
  case "$cmd" in
    add) _claude_acc_add "$@" ;;
    remove) _claude_acc_remove "$@" ;;
    list) _claude_acc_list ;;
    sync) _claude_acc_sync ;;
    help | -h | --help) _claude_acc_help ;;
    *)
      _claude_acc_log "unknown command: $cmd"
      _claude_acc_help
      return 1
      ;;
  esac
}

_claude_acc_load
