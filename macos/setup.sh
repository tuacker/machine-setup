#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS only."
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE_URL="https://raw.githubusercontent.com/tuacker/machine-setup/main/macos/Brewfile"
BREWFILE_PATH="$SCRIPT_DIR/Brewfile"
BREWFILE=""
BREWFILE_TMP=""

usage() {
  cat <<'USAGE'
Usage: macos/setup.sh [options]

Options:
  --global-only     Run global setup only.
  --user-only       Run per-user setup + defaults only.
  --defaults-only   Run macOS defaults only.
  --skip-global     Skip global setup.
  --skip-user       Skip per-user setup.
  --skip-defaults   Skip macOS defaults.
  -h, --help        Show this help.
USAGE
}

RUN_GLOBAL="auto"
RUN_USER="auto"
RUN_DEFAULTS="auto"

for arg in "$@"; do
  case "$arg" in
    --global-only)
      RUN_GLOBAL="force"
      RUN_USER="skip"
      RUN_DEFAULTS="skip"
      ;;
    --user-only)
      RUN_GLOBAL="skip"
      RUN_USER="force"
      RUN_DEFAULTS="force"
      ;;
    --defaults-only)
      RUN_GLOBAL="skip"
      RUN_USER="skip"
      RUN_DEFAULTS="force"
      ;;
    --skip-global)
      RUN_GLOBAL="skip"
      ;;
    --skip-user)
      RUN_USER="skip"
      ;;
    --skip-defaults)
      RUN_DEFAULTS="skip"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      usage
      exit 1
      ;;
  esac
done

log() {
  printf '%s\n' "$*"
}

cleanup() {
  if [[ -n "$BREWFILE_TMP" && -f "$BREWFILE_TMP" ]]; then
    rm -f "$BREWFILE_TMP"
  fi
}

trap cleanup EXIT

find_brew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    echo "/opt/homebrew/bin/brew"
    return 0
  fi
  if [[ -x /usr/local/bin/brew ]]; then
    echo "/usr/local/bin/brew"
    return 0
  fi
  return 1
}

resolve_brewfile() {
  if [[ -f "$BREWFILE_PATH" ]]; then
    BREWFILE="$BREWFILE_PATH"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    BREWFILE_TMP="$(mktemp -t machine-setup-brewfile)"
    if curl -fsSL "$BREWFILE_URL" -o "$BREWFILE_TMP"; then
      BREWFILE="$BREWFILE_TMP"
      return 0
    fi
  fi

  return 1
}

need_global() {
  local target_name="bodipro"
  local current_name
  local brew_bin

  current_name="$(scutil --get ComputerName 2>/dev/null || true)"
  if [[ "$current_name" != "$target_name" ]]; then
    return 0
  fi

  if ! xcode-select -p >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -d /Applications/Xcode.app ]]; then
    return 0
  fi

  if ! brew_bin="$(find_brew)"; then
    return 0
  fi

  if ! resolve_brewfile; then
    return 0
  fi

  if ! HOMEBREW_BUNDLE_MAS_SKIP=1 "$brew_bin" bundle check --file "$BREWFILE" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

ensure_line() {
  local file="$1"
  local line="$2"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if command -v rg >/dev/null 2>&1; then
    if ! rg -qF -- "$line" "$file"; then
      printf '%s\n' "$line" >> "$file"
    fi
  else
    if ! grep -Fq -- "$line" "$file"; then
      printf '%s\n' "$line" >> "$file"
    fi
  fi
}

global_setup() {
  local target_name="bodipro"
  local current_name
  local brew_bin
  local brew_prefix
  local mas_bin

  current_name="$(scutil --get ComputerName 2>/dev/null || true)"
  if [[ "$current_name" != "$target_name" ]]; then
    log "Setting machine name to $target_name (requires sudo)."
    sudo scutil --set ComputerName "$target_name"
    sudo scutil --set HostName "$target_name"
    sudo scutil --set LocalHostName "$target_name"
  else
    log "Machine name already set to $target_name."
  fi

  if xcode-select -p >/dev/null 2>&1; then
    log "Xcode Command Line Tools already installed."
  else
    log "Installing Xcode Command Line Tools."
    xcode-select --install || true
    while ! xcode-select -p >/dev/null 2>&1; do
      read -r -p "Finish the installer, then press Enter to continue..." _
    done
  fi

  if ! brew_bin="$(find_brew)"; then
    log "Installing Homebrew."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew_bin="$(find_brew)"
  fi

  if [[ -z "$brew_bin" ]]; then
    log "Homebrew not found after install."
    exit 1
  fi

  eval "$("$brew_bin" shellenv)"

  brew_prefix="$($brew_bin --prefix)"
  mas_bin="$brew_prefix/bin/mas"

  if [[ ! -x "$mas_bin" ]]; then
    log "Installing mas."
    "$brew_bin" install mas
  fi

  if ! resolve_brewfile; then
    log "Brewfile not found locally and could not be downloaded."
    log "Clone the repo or check network access, then re-run."
    exit 1
  fi

  until "$mas_bin" account >/dev/null 2>&1; do
    log "Sign in to the App Store to enable MAS installs (for Xcode)."
    read -r -p "Press Enter once signed in..." _
  done

  log "Running brew bundle."
  "$brew_bin" bundle --file "$BREWFILE"
}

user_setup() {
  local brew_bin
  local brew_shellenv_line=""
  local zprofile="$HOME/.zprofile"
  local zshrc="$HOME/.zshrc"

  if brew_bin="$(find_brew)"; then
    eval "$("$brew_bin" shellenv)"
    if [[ "$brew_bin" == "/opt/homebrew/bin/brew" ]]; then
      brew_shellenv_line='eval "$(/opt/homebrew/bin/brew shellenv)"'
    elif [[ "$brew_bin" == "/usr/local/bin/brew" ]]; then
      brew_shellenv_line='eval "$(/usr/local/bin/brew shellenv)"'
    fi
  fi

  if [[ -n "$brew_shellenv_line" ]]; then
    ensure_line "$zprofile" "$brew_shellenv_line"
  fi

  ensure_line "$zprofile" 'export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'
  ensure_line "$zprofile" 'export PNPM_HOME="$HOME/Library/pnpm"'
  ensure_line "$zprofile" 'export PATH="$PNPM_HOME:$PATH"'

  ensure_line "$zshrc" 'eval "$(mise activate zsh)"'
  ensure_line "$zshrc" "alias cy='codex --yolo'"

  if command -v git >/dev/null 2>&1; then
    git config --global user.name "Markus Bodner"
    git config --global user.email "me@markusbodner.com"
  fi

  local gitignore_global="$HOME/.gitignore_global"
  for line in \
    ".DS_Store" \
    ".AppleDouble" \
    ".LSOverride" \
    "._*" \
    ".Trashes"; do
    ensure_line "$gitignore_global" "$line"
  done

  git config --global core.excludesfile "$gitignore_global"

  local mise_bin=""
  if command -v mise >/dev/null 2>&1; then
    mise_bin="$(command -v mise)"
  elif [[ -x /opt/homebrew/bin/mise ]]; then
    mise_bin="/opt/homebrew/bin/mise"
  elif [[ -x /usr/local/bin/mise ]]; then
    mise_bin="/usr/local/bin/mise"
  fi

  if [[ -n "$mise_bin" ]]; then
    eval "$($mise_bin activate bash)"
    "$mise_bin" use -g node@lts
    "$mise_bin" exec node@lts -- corepack enable
    "$mise_bin" exec node@lts -- corepack prepare pnpm@latest --activate
    "$mise_bin" exec node@lts -- pnpm add -g @openai/codex
  else
    log "mise not found. Run global setup first."
  fi

  local op_bin=""
  if command -v op >/dev/null 2>&1; then
    op_bin="$(command -v op)"
  elif [[ -x /opt/homebrew/bin/op ]]; then
    op_bin="/opt/homebrew/bin/op"
  elif [[ -x /usr/local/bin/op ]]; then
    op_bin="/usr/local/bin/op"
  fi

  if [[ -n "$op_bin" ]]; then
    if ! "$op_bin" account list >/dev/null 2>&1; then
      log "Add your 1Password account."
      "$op_bin" account add
    fi

    if ! "$op_bin" whoami >/dev/null 2>&1; then
      log "Sign in to 1Password."
      eval "$("$op_bin" signin)"
    fi

    local op_ssh_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    if [[ ! -S "$op_ssh_sock" ]]; then
      log "Enable the 1Password SSH agent (Settings -> Developer) and unlock the app."
      while [[ ! -S "$op_ssh_sock" ]]; do
        read -r -p "Press Enter once the agent is enabled..." _
      done
    fi
  else
    log "1Password CLI not found. Install it via the Brewfile."
  fi
}

defaults_setup() {
  defaults write com.apple.dock show-recents -bool false
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock magnification -bool true
  defaults write com.apple.dock largesize -int 70

  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  defaults write com.apple.finder NewWindowTarget -string "PfHm"

  defaults write -g AppleShowAllExtensions -bool true
  defaults write -g ApplePressAndHoldEnabled -bool false
  defaults write -g KeyRepeat -int 2
  defaults write -g InitialKeyRepeat -int 15

  defaults write com.apple.Safari AutoFillPasswords -bool false

  if command -v duti >/dev/null 2>&1; then
    local ghostty_id
    ghostty_id="$(osascript -e 'id of app "Ghostty"' 2>/dev/null || true)"
    if [[ -z "$ghostty_id" ]]; then
      ghostty_id="com.mitchellh.ghostty"
    fi

    if [[ -d /Applications/Ghostty.app ]]; then
      duti -s "$ghostty_id" public.shell-script all
      duti -s "$ghostty_id" public.unix-executable all
      duti -s "$ghostty_id" public.script all
      duti -s "$ghostty_id" com.apple.terminal.shell-script all
      log "Set Ghostty as default terminal handler."
    else
      log "Ghostty not found in /Applications; skipping default terminal setup."
    fi
  else
    log "duti not found; skipping default terminal setup."
  fi

  killall Dock >/dev/null 2>&1 || true
  killall Finder >/dev/null 2>&1 || true
  killall SystemUIServer >/dev/null 2>&1 || true
  killall Safari >/dev/null 2>&1 || true

  log "macOS defaults applied. Some changes may require an app restart or logout/login."
}

manual_steps() {
  cat <<'EOF'

Manual steps:
- System Settings -> Passwords -> AutoFill Passwords and Passkeys: disable (use 1Password)
- System Settings -> Notifications: disable notification sounds per-app (no global toggle)
- Appearance: set Sidebar icon size to Small (System Settings -> Appearance)
- Finder: customize sidebar favorites to your liking
- Calendar: add Fastmail account (CalDAV) following https://www.fastmail.help/hc/en-us/articles/1500000277682-Automatic-setup-on-Mac
EOF
}

print_brewfile_summary() {
  local items

  if ! resolve_brewfile; then
    log "Brewfile not available; skipping installed apps list."
    return
  fi

  printf '%s\n' "" "Brewfile entries:"

  items="$(awk -F '\"' '/^brew "/ {print $2}' "$BREWFILE" | paste -sd ', ' -)"
  if [[ -n "$items" ]]; then
    printf 'CLI tools: %s\n' "$items"
  fi

  items="$(awk -F '\"' '/^cask "/ {print $2}' "$BREWFILE" | paste -sd ', ' -)"
  if [[ -n "$items" ]]; then
    printf 'Apps (casks): %s\n' "$items"
  fi

  items="$(awk -F '\"' '/^mas "/ {print $2}' "$BREWFILE" | paste -sd ', ' -)"
  if [[ -n "$items" ]]; then
    printf 'App Store (mas): %s\n' "$items"
  fi
}

if [[ "$RUN_GLOBAL" == "auto" ]]; then
  if need_global; then
    RUN_GLOBAL="force"
  else
    RUN_GLOBAL="skip"
  fi
fi

if [[ "$RUN_USER" == "auto" ]]; then
  RUN_USER="force"
fi

if [[ "$RUN_DEFAULTS" == "auto" ]]; then
  RUN_DEFAULTS="force"
fi

if [[ "$RUN_GLOBAL" == "force" ]]; then
  global_setup
fi

if [[ "$RUN_USER" == "force" ]]; then
  user_setup
fi

if [[ "$RUN_DEFAULTS" == "force" ]]; then
  defaults_setup
fi

print_brewfile_summary
manual_steps
