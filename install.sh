#!/usr/bin/env bash
# Installs claude-accounts.sh into the home directory and sources it from the shell rc file.
# Safe to run again: it updates the script and never adds the source line twice.
#
#   curl -fsSL https://raw.githubusercontent.com/MehmetSert/claude-code-multiple-accounts/main/install.sh | bash

set -euo pipefail

DEFAULT_SCRIPT_URL="https://raw.githubusercontent.com/MehmetSert/claude-code-multiple-accounts/main/claude-accounts.sh"
SCRIPT_URL="${CLAUDE_ACCOUNTS_SCRIPT_URL:-$DEFAULT_SCRIPT_URL}"
TARGET="$HOME/.claude-accounts.sh"
SOURCE_LINE='source ~/.claude-accounts.sh'
RC_MARKER='.claude-accounts.sh'

fail() {
  echo "install: $*" >&2
  exit 1
}

download_script() {
  local tmp="$TARGET.tmp.$$"
  if ! curl -fsSL "$SCRIPT_URL" -o "$tmp"; then
    rm -f "$tmp"
    fail "could not download $SCRIPT_URL"
  fi
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    fail "downloaded file is empty"
  fi
  mv "$tmp" "$TARGET"
  echo "Installed $TARGET"
}

detect_rc_file() {
  # Prints the rc file of the user's login shell, or nothing for unsupported shells
  case "${SHELL##*/}" in
    zsh) echo "${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash)
      # macOS terminals start login shells, which read .bash_profile instead of .bashrc
      if [ "$(uname)" = "Darwin" ] && [ ! -f "$HOME/.bashrc" ]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
  esac
}

add_source_line() {
  local rc="$1"
  if [ -f "$rc" ] && grep -qF -- "$RC_MARKER" "$rc"; then
    echo "$rc already sources the script"
    return 0
  fi
  printf '\n# Claude Code multiple accounts\n%s\n' "$SOURCE_LINE" >> "$rc"
  echo "Added '$SOURCE_LINE' to $rc"
}

warn_missing_tools() {
  local tool
  for tool in rsync jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Note: '$tool' is not installed. See the README for what it is used for."
    fi
  done
}

main() {
  local rc
  command -v curl >/dev/null 2>&1 || fail "curl is required"
  download_script
  rc="$(detect_rc_file)"
  if [ -z "$rc" ]; then
    echo "Unsupported shell '${SHELL:-unknown}' (zsh or bash is required)."
    echo "Add this line to your shell rc file yourself: $SOURCE_LINE"
    exit 0
  fi
  add_source_line "$rc"
  warn_missing_tools
  echo
  echo "Open a new terminal, then add an account:"
  echo "  claude-accounts add claude-work"
}

main "$@"
