#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS only."
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]-$0}")" && pwd)"
BREWFILE_URL="https://raw.githubusercontent.com/tuacker/machine-setup/main/macos/Brewfile"
BREWFILE_PATH="$SCRIPT_DIR/Brewfile"
BREWFILE=""
BREWFILE_TMP=""
BREW_BIN=""
BREW_PREFIX=""
DOTNET_RELEASE_INDEX_URL="https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"

TARGET_MACHINE_NAME="bodipro"
LOG_DIR="$HOME/Library/Logs/machine-setup"
LOG_FILE=""

DRY_RUN="false"
FORCE_ONLY="false"
ONLY_LIST=()
SKIP_LIST=()

SELECTED_SET="|"
SKIP_SET="|"

SUMMARY_INSTALLED=()
SUMMARY_CHANGED=()
SUMMARY_SKIPPED=()
SUMMARY_FAILED=()
SUMMARY_PLANNED=()

usage() {
  cat <<'USAGE'
Usage: macos/setup.sh [options]

Options:
  --dry-run, --plan     Show what would run and why, without changes.
  --only=a,b            Run only specific sections (comma-separated).
  --skip=a,b            Skip specific sections (comma-separated).

Legacy shorthands:
  --global-only         Equivalent to --only=global
  --user-only           Equivalent to --only=user
  --defaults-only       Equivalent to --only=defaults
  --skip-global         Equivalent to --skip=global
  --skip-user           Equivalent to --skip=user
  --skip-defaults       Equivalent to --skip=defaults
  -h, --help            Show this help.

Sections (use with --only/--skip):
  Groups:
    global     = machine, xcode, brew, apps, dotnet
    user       = user-shell, 1password, git, mise, rustup
    defaults   = macOS defaults (Dock/Finder/Safari/etc.)

  Steps:
    machine    = computer name
    xcode      = Xcode Command Line Tools
    brew       = install Homebrew
    apps       = Brewfile bundle (formulae/casks/mas)
    dotnet     = .NET SDK (official Microsoft pkg)
    user-shell = ~/.zprofile, ~/.zshrc, starship config
    1password  = sign in 1Password CLI + SSH agent
    git        = git name/email/default branch + global ignore
    mise       = node/pnpm/codex via mise
    rustup     = Rust toolchain manager
USAGE
}

log() {
  printf '%s\n' "$*"
}

prompt_user() {
  local message="$1"
  if [[ -t 0 ]]; then
    read -r -p "$message" _
  else
    read -r -p "$message" _ </dev/tty
  fi
}

init_log() {
  local timestamp
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  LOG_FILE="$LOG_DIR/${timestamp}-machine-setup.log"
  mkdir -p "$LOG_DIR"
  touch "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  log "Log file: $LOG_FILE"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

add_only() {
  local list="$1"
  local token
  IFS=',' read -r -a tokens <<< "$list"
  if [[ ${#tokens[@]} -gt 0 ]]; then
    for token in "${tokens[@]}"; do
      token="$(trim "$token")"
      if [[ -n "$token" ]]; then
        ONLY_LIST+=("$token")
      fi
    done
  fi
}

add_skip() {
  local list="$1"
  local token
  IFS=',' read -r -a tokens <<< "$list"
  if [[ ${#tokens[@]} -gt 0 ]]; then
    for token in "${tokens[@]}"; do
      token="$(trim "$token")"
      if [[ -n "$token" ]]; then
        SKIP_LIST+=("$token")
      fi
    done
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Missing value for --only"
        usage
        exit 1
      fi
      add_only "$1"
      ;;
    --only=*)
      add_only "${1#*=}"
      ;;
    --skip)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Missing value for --skip"
        usage
        exit 1
      fi
      add_skip "$1"
      ;;
    --skip=*)
      add_skip "${1#*=}"
      ;;
    --dry-run|--plan)
      DRY_RUN="true"
      ;;
    --global-only)
      add_only "global"
      ;;
    --user-only)
      add_only "user"
      ;;
    --defaults-only)
      add_only "defaults"
      ;;
    --skip-global)
      add_skip "global"
      ;;
    --skip-user)
      add_skip "user"
      ;;
    --skip-defaults)
      add_skip "defaults"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ ${#ONLY_LIST[@]} -gt 0 ]]; then
  FORCE_ONLY="true"
fi

cleanup() {
  if [[ -n "$BREWFILE_TMP" && -f "$BREWFILE_TMP" ]]; then
    rm -f "$BREWFILE_TMP"
  fi
}

trap cleanup EXIT

set_has() {
  local set="$1"
  local item="$2"
  [[ "$set" == *"|$item|"* ]]
}

selected_add() {
  local item="$1"
  if ! set_has "$SELECTED_SET" "$item"; then
    SELECTED_SET="${SELECTED_SET}|$item|"
  fi
}

selected_remove() {
  local item="$1"
  SELECTED_SET="${SELECTED_SET//|$item|/|}"
}

skip_add() {
  local item="$1"
  if ! set_has "$SKIP_SET" "$item"; then
    SKIP_SET="${SKIP_SET}|$item|"
  fi
}

expand_token() {
  case "$1" in
    global)
      echo "machine_name xcode_clt brew_install brew_bundle dotnet_pkg"
      ;;
    user)
      echo "user_shell one_password git_config mise_setup rustup_setup"
      ;;
    defaults)
      echo "defaults"
      ;;
    brew)
      echo "brew_install"
      ;;
    apps|bundle)
      echo "brew_bundle"
      ;;
    user-shell|shell|zsh)
      echo "user_shell"
      ;;
    1password|1p|op)
      echo "one_password"
      ;;
    git)
      echo "git_config"
      ;;
    mise)
      echo "mise_setup"
      ;;
    rust|rustup)
      echo "rustup_setup"
      ;;
    dotnet)
      echo "dotnet_pkg"
      ;;
    machine)
      echo "machine_name"
      ;;
    xcode|xcode-clt)
      echo "xcode_clt"
      ;;
    *)
      return 1
      ;;
  esac
}

ALL_STEPS=(
  machine_name
  xcode_clt
  brew_install
  brew_bundle
  dotnet_pkg
  user_shell
  one_password
  git_config
  mise_setup
  rustup_setup
  defaults
)

build_sets() {
  local token
  local step
  local steps

  SELECTED_SET="|"
  SKIP_SET="|"

  if [[ ${#ONLY_LIST[@]} -gt 0 ]]; then
    for token in "${ONLY_LIST[@]}"; do
      if ! steps="$(expand_token "$token")"; then
        echo "Unknown section: $token"
        usage
        exit 1
      fi
      for step in $steps; do
        selected_add "$step"
      done
    done
  else
    for step in "${ALL_STEPS[@]}"; do
      selected_add "$step"
    done
  fi

  if [[ ${#SKIP_LIST[@]} -gt 0 ]]; then
    for token in "${SKIP_LIST[@]}"; do
      if [[ -z "$token" ]]; then
        continue
      fi
      if ! steps="$(expand_token "$token")"; then
        echo "Unknown section: $token"
        usage
        exit 1
      fi
      for step in $steps; do
        skip_add "$step"
      done
    done
  fi

  if set_has "$SELECTED_SET" "brew_bundle"; then
    selected_add "brew_install"
    selected_add "xcode_clt"
  fi
  if set_has "$SELECTED_SET" "brew_install"; then
    selected_add "xcode_clt"
  fi
  if set_has "$SELECTED_SET" "mise_setup"; then
    selected_add "brew_bundle"
    selected_add "brew_install"
    selected_add "xcode_clt"
  fi
  if set_has "$SELECTED_SET" "one_password"; then
    selected_add "brew_bundle"
    selected_add "brew_install"
    selected_add "xcode_clt"
  fi

  for step in "${ALL_STEPS[@]}"; do
    if set_has "$SKIP_SET" "$step"; then
      selected_remove "$step"
    fi
  done
}

label_for_step() {
  case "$1" in
    machine_name)
      echo "Machine name"
      ;;
    xcode_clt)
      echo "Xcode Command Line Tools"
      ;;
    brew_install)
      echo "Homebrew"
      ;;
    brew_bundle)
      echo "Brewfile bundle"
      ;;
    user_shell)
      echo "Shell config"
      ;;
    one_password)
      echo "1Password CLI"
      ;;
    git_config)
      echo "Git config"
      ;;
    mise_setup)
      echo "Mise + Node/pnpm/Codex"
      ;;
    rustup_setup)
      echo "Rustup"
      ;;
    dotnet_pkg)
      echo ".NET SDK"
      ;;
    defaults)
      echo "macOS defaults"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

summary_installed() {
  SUMMARY_INSTALLED+=("$1")
}

summary_changed() {
  SUMMARY_CHANGED+=("$1")
}

summary_skipped() {
  SUMMARY_SKIPPED+=("$1")
}

summary_failed() {
  SUMMARY_FAILED+=("$1")
}

summary_planned() {
  SUMMARY_PLANNED+=("$1")
}

print_summary_section() {
  local title="$1"
  shift
  if [[ $# -eq 0 ]]; then
    return 0
  fi
  printf '\n%s:\n' "$title"
  for item in "$@"; do
    printf -- '- %s\n' "$item"
  done
}

print_summary() {
  if [[ ${#SUMMARY_INSTALLED[@]} -gt 0 ]]; then
    print_summary_section "Installed" "${SUMMARY_INSTALLED[@]}"
  fi
  if [[ ${#SUMMARY_CHANGED[@]} -gt 0 ]]; then
    print_summary_section "Changed" "${SUMMARY_CHANGED[@]}"
  fi
  if [[ ${#SUMMARY_SKIPPED[@]} -gt 0 ]]; then
    print_summary_section "Skipped" "${SUMMARY_SKIPPED[@]}"
  fi
  if [[ ${#SUMMARY_FAILED[@]} -gt 0 ]]; then
    print_summary_section "Failed" "${SUMMARY_FAILED[@]}"
  fi
}

print_plan() {
  printf '\nPlan (dry run):\n'
  if [[ ${#SUMMARY_PLANNED[@]} -eq 0 ]]; then
    printf '%s\n' "No changes needed."
    return 0
  fi
  for item in "${SUMMARY_PLANNED[@]}"; do
    printf -- '- %s\n' "$item"
  done
}

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

ensure_brew_env() {
  local brew_bin=""
  if brew_bin="$(find_brew)"; then
    BREW_BIN="$brew_bin"
    eval "$("$BREW_BIN" shellenv)"
    BREW_PREFIX="$("$BREW_BIN" --prefix)"
  else
    BREW_BIN=""
    BREW_PREFIX=""
  fi
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

line_missing() {
  local file="$1"
  local line="$2"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  if command -v rg >/dev/null 2>&1; then
    if rg -qFx -- "$line" "$file"; then
      return 1
    fi
  else
    if grep -Fqx -- "$line" "$file"; then
      return 1
    fi
  fi

  return 0
}

ensure_line() {
  local file="$1"
  local line="$2"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if line_missing "$file" "$line"; then
    printf '%s\n' "$line" >> "$file"
    return 0
  fi

  return 1
}

write_file_if_changed() {
  local file="$1"
  local tmp

  tmp="$(mktemp -t machine-setup-file)"
  cat > "$tmp"

  if [[ -f "$file" ]] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi

  mkdir -p "$(dirname "$file")"
  mv "$tmp" "$file"
  return 0
}

starship_config_content() {
  cat <<'EOF'
format = """
$username at $hostname in $directory$git_branch$git_status$custom$status
$character
"""

[username]
show_always = true
format = "[$user]($style)"

[hostname]
ssh_only = false
format = "[$hostname]($style)"

[directory]
truncation_length = 4
truncation_symbol = ""
truncate_to_repo = false
home_symbol = "~"
read_only = ""
format = "[$path]($style)"

[git_branch]
format = " on [$symbol$branch]($style)"

[git_status]
format = " [\\[$all_status$ahead_behind\\]]($style)"

[status]
disabled = false
format = ' status: [$symbol \($status\)]($style)'
success_symbol = "ok"
symbol = "err"
success_style = "green"
failure_style = "red"

[custom.codex]
command = 'basename "$CODEX_HOME"'
when = '[ -n "$CODEX_HOME" ] && [ "$(basename "$CODEX_HOME")" != ".codex" ]'
format = ' [$output]($style)'
style = 'yellow'
EOF
}

starship_config_differs() {
  local file="$1"
  local tmp

  tmp="$(mktemp -t machine-setup-starship)"
  starship_config_content > "$tmp"

  if [[ -f "$file" ]] && cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi

  rm -f "$tmp"
  return 0
}

NEED_REASON=""

need_machine_name() {
  local current
  current="$(scutil --get ComputerName 2>/dev/null || true)"
  if [[ "$current" != "$TARGET_MACHINE_NAME" ]]; then
    NEED_REASON="current name is ${current:-unset}"
    return 0
  fi
  return 1
}

need_xcode_clt() {
  if ! xcode-select -p >/dev/null 2>&1; then
    NEED_REASON="Xcode Command Line Tools not installed"
    return 0
  fi
  return 1
}

need_brew_install() {
  if ! find_brew >/dev/null 2>&1; then
    NEED_REASON="Homebrew not installed"
    return 0
  fi
  return 1
}

need_brew_bundle() {
  local brew_bin

  if ! brew_bin="$(find_brew)"; then
    NEED_REASON="Homebrew not installed"
    return 0
  fi

  if ! resolve_brewfile; then
    NEED_REASON="Brewfile missing or unavailable"
    return 0
  fi

  if ! "$brew_bin" bundle check --file "$BREWFILE" >/dev/null 2>&1; then
    NEED_REASON="Brewfile dependencies not installed"
    return 0
  fi

  return 1
}

need_user_shell() {
  local zprofile="$HOME/.zprofile"
  local zshrc="$HOME/.zshrc"
  local brew_bin=""
  local brew_shellenv_line=""
  local missing=()
  local line
  local zprofile_lines=()
  local zshrc_lines=()

  if brew_bin="$(find_brew)"; then
    if [[ "$brew_bin" == "/opt/homebrew/bin/brew" ]]; then
      brew_shellenv_line='eval "$(/opt/homebrew/bin/brew shellenv)"'
    elif [[ "$brew_bin" == "/usr/local/bin/brew" ]]; then
      brew_shellenv_line='eval "$(/usr/local/bin/brew shellenv)"'
    fi
  fi

  if [[ -n "$brew_shellenv_line" ]] && line_missing "$zprofile" "$brew_shellenv_line"; then
    missing+=("brew shellenv")
  fi

  zprofile_lines=(
    'export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'
    'export PNPM_HOME="$HOME/Library/pnpm"'
    'export PATH="$PNPM_HOME:$PATH"'
    'export PATH="$HOME/.cargo/bin:$PATH"'
  )

  for line in "${zprofile_lines[@]}"; do
    if line_missing "$zprofile" "$line"; then
      missing+=(".zprofile")
      break
    fi
  done

  zshrc_lines=(
    'eval "$(mise activate zsh)"'
    'autoload -Uz compinit'
    'compinit'
    'zstyle ":completion:*" matcher-list "m:{a-zA-Z}={A-Za-z}"'
    'eval "$(direnv hook zsh)"'
    'eval "$(starship init zsh)"'
    "alias cy='codex --yolo --search'"
    'yt(){ yt-dlp -f "bv*+ba/b" --write-subs --sub-langs "en" --sub-format "srt/best" --convert-subs srt --cookies-from-browser firefox "$@"; }'
  )

  for line in "${zshrc_lines[@]}"; do
    if line_missing "$zshrc" "$line"; then
      missing+=(".zshrc")
      break
    fi
  done

  if starship_config_differs "$HOME/.config/starship.toml"; then
    missing+=("starship config")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    NEED_REASON="missing shell config lines or starship config"
    return 0
  fi

  return 1
}

need_one_password() {
  local op_bin=""
  local op_ssh_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

  if command -v op >/dev/null 2>&1; then
    op_bin="$(command -v op)"
  elif [[ -x /opt/homebrew/bin/op ]]; then
    op_bin="/opt/homebrew/bin/op"
  elif [[ -x /usr/local/bin/op ]]; then
    op_bin="/usr/local/bin/op"
  fi

  if [[ -z "$op_bin" ]]; then
    NEED_REASON="1Password CLI not installed"
    return 0
  fi

  if ! "$op_bin" whoami >/dev/null 2>&1; then
    NEED_REASON="1Password CLI not signed in"
    return 0
  fi

  if [[ ! -S "$op_ssh_sock" ]]; then
    NEED_REASON="1Password SSH agent not enabled"
    return 0
  fi

  return 1
}

need_git_config() {
  local missing=0
  local gitignore_global="$HOME/.gitignore_global"
  local line
  local gitignore_lines=(
    ".DS_Store"
    ".AppleDouble"
    ".LSOverride"
    "._*"
    ".Trashes"
  )

  if ! command -v git >/dev/null 2>&1; then
    NEED_REASON="git not installed"
    return 0
  fi

  if [[ "$(git config --global user.name || true)" != "Markus Bodner" ]]; then
    missing=1
  fi
  if [[ "$(git config --global user.email || true)" != "me@markusbodner.com" ]]; then
    missing=1
  fi
  if [[ "$(git config --global init.defaultBranch || true)" != "main" ]]; then
    missing=1
  fi

  for line in "${gitignore_lines[@]}"; do
    if line_missing "$gitignore_global" "$line"; then
      missing=1
      break
    fi
  done

  if [[ "$(git config --global core.excludesfile || true)" != "$gitignore_global" ]]; then
    missing=1
  fi

  if [[ "$missing" -eq 1 ]]; then
    NEED_REASON="git config or global ignore missing"
    return 0
  fi

  return 1
}

need_mise_setup() {
  if ! command -v mise >/dev/null 2>&1; then
    NEED_REASON="mise not installed"
    return 0
  fi

  if ! command -v node >/dev/null 2>&1; then
    NEED_REASON="node not installed"
    return 0
  fi

  if ! command -v pnpm >/dev/null 2>&1; then
    NEED_REASON="pnpm not installed"
    return 0
  fi

  if ! command -v codex >/dev/null 2>&1; then
    NEED_REASON="codex not installed"
    return 0
  fi

  return 1
}

need_dotnet_pkg() {
  if ! command -v dotnet >/dev/null 2>&1; then
    NEED_REASON=".NET SDK not installed"
    return 0
  fi
  return 1
}

need_rustup_setup() {
  if ! command -v rustup >/dev/null 2>&1; then
    NEED_REASON="rustup not installed"
    return 0
  fi
  return 1
}

normalize_bool() {
  case "$1" in
    1|true|TRUE|yes|YES)
      echo "1"
      ;;
    0|false|FALSE|no|NO)
      echo "0"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

defaults_read() {
  local domain="$1"
  local key="$2"
  defaults read "$domain" "$key" 2>/dev/null || true
}

need_defaults() {
  local mismatches=()
  local value

  value="$(normalize_bool "$(defaults_read com.apple.dock show-recents)")"
  [[ "$value" == "0" ]] || mismatches+=("dock.show-recents")

  value="$(normalize_bool "$(defaults_read com.apple.dock autohide)")"
  [[ "$value" == "1" ]] || mismatches+=("dock.autohide")

  value="$(normalize_bool "$(defaults_read com.apple.dock magnification)")"
  [[ "$value" == "1" ]] || mismatches+=("dock.magnification")

  value="$(defaults_read com.apple.dock largesize)"
  [[ "$value" == "70" ]] || mismatches+=("dock.largesize")

  value="$(normalize_bool "$(defaults_read com.apple.dock mru-spaces)")"
  [[ "$value" == "0" ]] || mismatches+=("dock.mru-spaces")

  value="$(defaults_read com.apple.finder FXPreferredViewStyle)"
  [[ "$value" == "Nlsv" ]] || mismatches+=("finder.view-style")

  value="$(defaults_read com.apple.finder NewWindowTarget)"
  [[ "$value" == "PfHm" ]] || mismatches+=("finder.new-window-target")

  value="$(normalize_bool "$(defaults_read -g AppleShowAllExtensions)")"
  [[ "$value" == "1" ]] || mismatches+=("show-all-extensions")

  value="$(normalize_bool "$(defaults_read -g ApplePressAndHoldEnabled)")"
  [[ "$value" == "0" ]] || mismatches+=("press-and-hold")

  value="$(defaults_read -g KeyRepeat)"
  [[ "$value" == "2" ]] || mismatches+=("key-repeat")

  value="$(defaults_read -g InitialKeyRepeat)"
  [[ "$value" == "15" ]] || mismatches+=("initial-key-repeat")

  value="$(normalize_bool "$(defaults_read com.apple.WindowManager EnableStandardClickToShowDesktop)")"
  [[ "$value" == "0" ]] || mismatches+=("show-desktop-on-wallpaper")

  value="$(normalize_bool "$(defaults_read com.apple.Safari AutoFillPasswords)")"
  if [[ -z "$value" ]]; then
    mismatches+=("safari.autofill-passwords (grant Full Disk Access)")
  elif [[ "$value" != "0" ]]; then
    mismatches+=("safari.autofill-passwords")
  fi

  if [[ ${#mismatches[@]} -gt 0 ]]; then
    NEED_REASON="defaults not set: ${mismatches[*]}"
    return 0
  fi

  return 1
}

step_machine_name() {
  local current
  current="$(scutil --get ComputerName 2>/dev/null || true)"
  if [[ "$current" == "$TARGET_MACHINE_NAME" ]]; then
    log "Machine name already set to $TARGET_MACHINE_NAME."
    summary_skipped "Machine name already set to $TARGET_MACHINE_NAME"
    return 0
  fi

  log "Setting machine name to $TARGET_MACHINE_NAME (requires sudo)."
  sudo scutil --set ComputerName "$TARGET_MACHINE_NAME"
  sudo scutil --set HostName "$TARGET_MACHINE_NAME"
  sudo scutil --set LocalHostName "$TARGET_MACHINE_NAME"
  summary_changed "Set machine name to $TARGET_MACHINE_NAME"
}

step_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log "Xcode Command Line Tools already installed."
    summary_skipped "Xcode Command Line Tools already installed"
    return 0
  fi

  log "Installing Xcode Command Line Tools."
  xcode-select --install || true
  while ! xcode-select -p >/dev/null 2>&1; do
    prompt_user "Finish the installer, then press Enter to continue..."
  done
  summary_installed "Xcode Command Line Tools"
}

step_brew_install() {
  local brew_bin

  if brew_bin="$(find_brew)"; then
    log "Homebrew already installed."
    summary_skipped "Homebrew already installed"
    BREW_BIN="$brew_bin"
    BREW_PREFIX="$("$BREW_BIN" --prefix)"
    eval "$("$BREW_BIN" shellenv)"
    return 0
  fi

  log "Installing Homebrew."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ensure_brew_env

  if [[ -z "$BREW_BIN" ]]; then
    log "Homebrew not found after install."
    summary_failed "Homebrew install failed"
    return 1
  fi

  summary_installed "Homebrew"
}

step_brew_bundle() {
  ensure_brew_env

  if [[ -z "$BREW_BIN" ]]; then
    log "Homebrew not found. Run brew install first."
    summary_failed "Brew bundle skipped (Homebrew missing)"
    return 1
  fi

  if ! resolve_brewfile; then
    log "Brewfile not found locally and could not be downloaded."
    log "Clone the repo or check network access, then re-run."
    summary_failed "Brewfile not available"
    return 1
  fi

  log "Sign in to the App Store to enable MAS installs (for Office apps)."
  open -a "App Store" >/dev/null 2>&1 || true
  prompt_user "Press Enter once signed in..."

  log "Running brew bundle."
  "$BREW_BIN" bundle --file "$BREWFILE"
  summary_installed "Brewfile dependencies"
}

step_dotnet_pkg() {
  local arch
  local rid
  local index_tmp
  local releases_tmp
  local releases_json_url
  local pkg_info
  local pkg_url
  local sdk_version
  local pkg_tmp

  if command -v dotnet >/dev/null 2>&1; then
    log ".NET SDK already installed."
    summary_skipped ".NET SDK already installed"
    return 0
  fi

  if ! command -v ruby >/dev/null 2>&1; then
    log "Ruby is required to parse .NET release metadata."
    summary_failed ".NET SDK install failed (ruby missing)"
    return 1
  fi

  arch="$(uname -m)"
  if [[ "$arch" == "arm64" ]]; then
    rid="osx-arm64"
  else
    rid="osx-x64"
  fi

  index_tmp="$(mktemp -t dotnet-release-index)"
  releases_tmp="$(mktemp -t dotnet-releases)"

  if ! curl -fsSL "$DOTNET_RELEASE_INDEX_URL" -o "$index_tmp"; then
    log "Failed to download .NET release index."
    summary_failed ".NET SDK install failed (release index)"
    rm -f "$index_tmp" "$releases_tmp"
    return 1
  fi

  releases_json_url="$(ruby -rjson -e '
data = JSON.parse(File.read(ARGV[0]))
channels = data["releases-index"].select { |r| r["release-type"] == "lts" }
channels = data["releases-index"] if channels.empty?
latest = channels.max_by { |r| r["channel-version"].to_f }
puts latest["releases.json"]
' "$index_tmp")"

  if [[ -z "$releases_json_url" ]]; then
    log "Failed to resolve .NET releases metadata URL."
    summary_failed ".NET SDK install failed (release metadata)"
    rm -f "$index_tmp" "$releases_tmp"
    return 1
  fi

  if ! curl -fsSL "$releases_json_url" -o "$releases_tmp"; then
    log "Failed to download .NET releases metadata."
    summary_failed ".NET SDK install failed (release metadata)"
    rm -f "$index_tmp" "$releases_tmp"
    return 1
  fi

  pkg_info="$(DOTNET_RID="$rid" ruby -rjson -e '
data = JSON.parse(File.read(ARGV[0]))
releases = data["releases"]
latest = releases.max_by { |r| r["release-date"] }
sdk = latest["sdk"] || {}
files = sdk["files"] || []
file = files.find { |f| f["rid"] == ENV["DOTNET_RID"] && f["url"] && f["url"].end_with?(".pkg") }
if file && file["url"]
  puts file["url"]
  puts sdk["version"]
end
' "$releases_tmp")"

  pkg_url="$(printf '%s\n' "$pkg_info" | sed -n '1p')"
  sdk_version="$(printf '%s\n' "$pkg_info" | sed -n '2p')"

  if [[ -z "$pkg_url" ]]; then
    log "Failed to resolve .NET SDK package URL."
    summary_failed ".NET SDK install failed (package URL)"
    rm -f "$index_tmp" "$releases_tmp"
    return 1
  fi

  pkg_tmp="$(mktemp -t dotnet-sdk).pkg"
  log "Downloading .NET SDK ${sdk_version:-latest} (${rid})."
  if ! curl -fL "$pkg_url" -o "$pkg_tmp"; then
    log "Failed to download .NET SDK package."
    summary_failed ".NET SDK install failed (download)"
    rm -f "$index_tmp" "$releases_tmp" "$pkg_tmp"
    return 1
  fi

  log "Installing .NET SDK (requires sudo)."
  if ! sudo installer -pkg "$pkg_tmp" -target /; then
    summary_failed ".NET SDK install failed (installer)"
    rm -f "$index_tmp" "$releases_tmp" "$pkg_tmp"
    return 1
  fi

  rm -f "$index_tmp" "$releases_tmp" "$pkg_tmp"
  if [[ -n "$sdk_version" ]]; then
    summary_installed ".NET SDK $sdk_version"
  else
    summary_installed ".NET SDK"
  fi
}

step_user_shell() {
  local brew_bin
  local brew_shellenv_line=""
  local zprofile="$HOME/.zprofile"
  local zshrc="$HOME/.zshrc"
  local shell_changed="false"
  local starship_changed="false"

  if brew_bin="$(find_brew)"; then
    if [[ "$brew_bin" == "/opt/homebrew/bin/brew" ]]; then
      brew_shellenv_line='eval "$(/opt/homebrew/bin/brew shellenv)"'
    elif [[ "$brew_bin" == "/usr/local/bin/brew" ]]; then
      brew_shellenv_line='eval "$(/usr/local/bin/brew shellenv)"'
    fi
  fi

  if [[ -n "$brew_shellenv_line" ]]; then
    if ensure_line "$zprofile" "$brew_shellenv_line"; then
      shell_changed="true"
    fi
  fi

  if ensure_line "$zprofile" 'export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'; then
    shell_changed="true"
  fi
  if ensure_line "$zprofile" 'export PNPM_HOME="$HOME/Library/pnpm"'; then
    shell_changed="true"
  fi
  if ensure_line "$zprofile" 'export PATH="$PNPM_HOME:$PATH"'; then
    shell_changed="true"
  fi
  if ensure_line "$zprofile" 'export PATH="$HOME/.cargo/bin:$PATH"'; then
    shell_changed="true"
  fi

  if ensure_line "$zshrc" 'eval "$(mise activate zsh)"'; then
    shell_changed="true"
  fi
  if ensure_line "$zshrc" 'autoload -Uz compinit'; then
    shell_changed="true"
  fi
  if ensure_line "$zshrc" 'compinit'; then
    shell_changed="true"
  fi
  if ensure_line "$zshrc" 'zstyle ":completion:*" matcher-list "m:{a-zA-Z}={A-Za-z}"'; then
    shell_changed="true"
  fi
  if ensure_line "$zshrc" 'eval "$(direnv hook zsh)"'; then
    shell_changed="true"
  fi
  if ensure_line "$zshrc" 'eval "$(starship init zsh)"'; then
    shell_changed="true"
  fi
  if ensure_line "$zshrc" "alias cy='codex --yolo --search'"; then
    shell_changed="true"
  fi
  if ensure_line "$zshrc" 'yt(){ yt-dlp -f "bv*+ba/b" --write-subs --sub-langs "en" --sub-format "srt/best" --convert-subs srt --cookies-from-browser firefox "$@"; }'; then
    shell_changed="true"
  fi

  if starship_config_content | write_file_if_changed "$HOME/.config/starship.toml"; then
    starship_changed="true"
  fi

  if [[ "$shell_changed" == "true" ]]; then
    summary_changed "Updated shell config (~/.zprofile, ~/.zshrc)"
  fi
  if [[ "$starship_changed" == "true" ]]; then
    summary_changed "Updated starship config (~/.config/starship.toml)"
  fi

  if [[ "$shell_changed" == "false" && "$starship_changed" == "false" ]]; then
    summary_skipped "Shell config already up to date"
  fi
}

step_one_password() {
  local op_bin=""
  local op_ssh_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

  if command -v op >/dev/null 2>&1; then
    op_bin="$(command -v op)"
  elif [[ -x /opt/homebrew/bin/op ]]; then
    op_bin="/opt/homebrew/bin/op"
  elif [[ -x /usr/local/bin/op ]]; then
    op_bin="/usr/local/bin/op"
  fi

  if [[ -z "$op_bin" ]]; then
    log "1Password CLI not found. Install it via the Brewfile."
    summary_skipped "1Password CLI not installed"
    return 0
  fi

  if "$op_bin" whoami >/dev/null 2>&1 && [[ -S "$op_ssh_sock" ]]; then
    summary_skipped "1Password already signed in and SSH agent enabled"
    return 0
  fi

  log "Open 1Password and sign in."
  open -a "1Password" >/dev/null 2>&1 || true
  prompt_user "Enable CLI integration (Settings -> Developer), then press Enter..."

  if ! "$op_bin" account list >/dev/null 2>&1; then
    log "Add your 1Password account."
    "$op_bin" account add
  fi

  if ! "$op_bin" whoami >/dev/null 2>&1; then
    log "Sign in to 1Password."
    eval "$("$op_bin" signin)"
  fi

  if [[ ! -S "$op_ssh_sock" ]]; then
    log "Enable the 1Password SSH agent (Settings -> Developer) and unlock the app."
    while [[ ! -S "$op_ssh_sock" ]]; do
      prompt_user "Press Enter once the agent is enabled..."
    done
  fi

  summary_changed "Configured 1Password CLI and SSH agent"
}

step_git_config() {
  local changed="false"
  local gitignore_global="$HOME/.gitignore_global"
  local line

  if ! command -v git >/dev/null 2>&1; then
    summary_skipped "git not installed"
    return 0
  fi

  if [[ "$(git config --global user.name || true)" != "Markus Bodner" ]]; then
    git config --global user.name "Markus Bodner"
    changed="true"
  fi

  if [[ "$(git config --global user.email || true)" != "me@markusbodner.com" ]]; then
    git config --global user.email "me@markusbodner.com"
    changed="true"
  fi
  if [[ "$(git config --global init.defaultBranch || true)" != "main" ]]; then
    git config --global init.defaultBranch "main"
    changed="true"
  fi

  for line in \
    ".DS_Store" \
    ".AppleDouble" \
    ".LSOverride" \
    "._*" \
    ".Trashes"; do
    if ensure_line "$gitignore_global" "$line"; then
      changed="true"
    fi
  done

  if [[ "$(git config --global core.excludesfile || true)" != "$gitignore_global" ]]; then
    git config --global core.excludesfile "$gitignore_global"
    changed="true"
  fi

  if [[ "$changed" == "true" ]]; then
    summary_changed "Updated git config and global ignore"
  else
    summary_skipped "Git config already up to date"
  fi
}

step_mise_setup() {
  local mise_bin=""

  if command -v mise >/dev/null 2>&1; then
    mise_bin="$(command -v mise)"
  elif [[ -x /opt/homebrew/bin/mise ]]; then
    mise_bin="/opt/homebrew/bin/mise"
  elif [[ -x /usr/local/bin/mise ]]; then
    mise_bin="/usr/local/bin/mise"
  fi

  if [[ -z "$mise_bin" ]]; then
    log "mise not found. Run brew bundle first."
    summary_skipped "mise not installed"
    return 0
  fi

  eval "$($mise_bin activate bash)"
  "$mise_bin" use -g node@lts
  "$mise_bin" exec node@lts -- corepack enable
  "$mise_bin" exec node@lts -- corepack prepare pnpm@latest --activate
  "$mise_bin" exec node@lts -- pnpm add -g @openai/codex
  summary_changed "Configured Node (mise), pnpm, and codex"
}

step_rustup_setup() {
  if command -v rustup >/dev/null 2>&1; then
    log "rustup already installed."
    summary_skipped "rustup already installed"
    return 0
  fi

  log "Installing rustup (Rust toolchain manager)."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  summary_installed "rustup"
}

step_defaults() {
  defaults write com.apple.dock show-recents -bool false
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock magnification -bool true
  defaults write com.apple.dock largesize -int 70
  defaults write com.apple.dock mru-spaces -bool false

  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  defaults write com.apple.finder NewWindowTarget -string "PfHm"

  defaults write -g AppleShowAllExtensions -bool true
  defaults write -g ApplePressAndHoldEnabled -bool false
  defaults write -g KeyRepeat -int 2
  defaults write -g InitialKeyRepeat -int 15

  defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false

  if ! defaults write com.apple.Safari AutoFillPasswords -bool false; then
    log "Unable to write Safari preferences."
    log "Grant Full Disk Access to your terminal and re-run, or set it manually."
    return 1
  fi

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

  summary_changed "Applied macOS defaults"
  log "macOS defaults applied. Some changes may require an app restart or logout/login."
}

run_step() {
  local step="$1"
  local func="$2"
  local need_func="$3"
  local label
  local needs="false"

  label="$(label_for_step "$step")"

  if ! set_has "$SELECTED_SET" "$step"; then
    if set_has "$SKIP_SET" "$step"; then
      summary_skipped "$label (skipped by flag)"
    fi
    return 0
  fi

  NEED_REASON=""
  if "$need_func"; then
    needs="true"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ "$needs" == "true" ]]; then
      summary_planned "$label: $NEED_REASON"
    elif [[ "$FORCE_ONLY" == "true" ]]; then
      summary_planned "$label: forced by --only"
    fi
    return 0
  fi

  if [[ "$needs" == "true" || "$FORCE_ONLY" == "true" ]]; then
    if ! "$func"; then
      summary_failed "$label failed"
      return 1
    fi
  else
    summary_skipped "$label already configured"
  fi
}

run_or_exit() {
  local step="$1"
  local func="$2"
  local need_func="$3"

  if ! run_step "$step" "$func" "$need_func"; then
    print_summary
    exit 1
  fi
}

manual_steps() {
  cat <<'EOF'

Manual steps:
- System Settings -> Apple ID -> iCloud -> iCloud Drive: disable "Optimize Mac Storage"
- System Settings -> Passwords -> AutoFill Passwords and Passkeys: disable (use 1Password)
- System Settings -> Notifications: disable notification sounds per-app (no global toggle)
- System Settings -> Appearance -> Sidebar icon size: Small
- System Settings -> Control Center: adjust menu bar items (e.g., Focus) to your preference
- Finder -> Settings -> Sidebar: customize favorites to your liking
- Finder -> View: Show Path Bar
- Calendar: add Fastmail account (CalDAV) following https://www.fastmail.help/hc/en-us/articles/1500000277682-Automatic-setup-on-Mac
- IINA -> Settings -> General: enable "Use legacy fullscreen"
- Work repo: add a `.envrc` with `export CODEX_HOME="$HOME/.codex-<project>"`, then run `direnv allow`
- Xcode: download from https://developer.apple.com/download/all/ then install with `unxip Xcode_*.xip /Applications`
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

print_shell_shortcuts() {
  cat <<'EOF'

Shell shortcuts:
- cy = codex --yolo
- yt = yt-dlp -f "bv*+ba/b" --write-subs --write-auto-subs --sub-langs "en.*,de.*" --sub-format "srt/best" --convert-subs srt <url>
EOF
}

build_sets
init_log

run_or_exit machine_name step_machine_name need_machine_name
run_or_exit xcode_clt step_xcode_clt need_xcode_clt
run_or_exit brew_install step_brew_install need_brew_install
run_or_exit brew_bundle step_brew_bundle need_brew_bundle
run_or_exit dotnet_pkg step_dotnet_pkg need_dotnet_pkg
run_or_exit user_shell step_user_shell need_user_shell
run_or_exit one_password step_one_password need_one_password
run_or_exit git_config step_git_config need_git_config
run_or_exit mise_setup step_mise_setup need_mise_setup
run_or_exit rustup_setup step_rustup_setup need_rustup_setup
run_or_exit defaults step_defaults need_defaults

if [[ "$DRY_RUN" == "true" ]]; then
  print_plan
  exit 0
fi

print_summary
print_brewfile_summary
print_shell_shortcuts
manual_steps
