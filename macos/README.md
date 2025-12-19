# macOS setup

## Goal

Write down the desired end state before automating anything.

## Target machine profile

- macOS fresh install (no restore from backup)
- Default shell: zsh
- Version manager: mise

## Desired end state (draft)

- Machine name set (ComputerName/HostName/LocalHostName) to `bodipro`. Command: `sudo scutil --set ComputerName "bodipro" && sudo scutil --set HostName "bodipro" && sudo scutil --set LocalHostName "bodipro"`
- Xcode Command Line Tools installed
- Homebrew installed and shellenv configured
- Brew bundle in place for core packages
- zsh configured for PATH and mise activation
- Node LTS installed via mise
- Corepack enabled
- pnpm installed and active
- Codex CLI installed
- Global gitignore configured for macOS noise files (e.g. .DS_Store)
- Git configured with user.name and user.email (Markus Bodner / me@markusbodner.com)
- Shell config policy: environment in .zprofile; interactive config in .zshrc
- Install 1Password early and pause for sign-in to unlock secrets
- Core apps: Ghostty, Spotify, Docker, Chrome, Firefox, Discord, Xcode, Sublime Merge, Alfred
- Install sources (planned):
- MAS: Xcode (requires App Store sign-in)
- Cask: 1Password, Ghostty, Spotify, Docker, Chrome, Firefox, Discord, Sublime Merge, Alfred
- 1Password CLI sign-in flow: `op account add` then `eval $(op signin)` (per CLI prompt)
- SSH keys managed in 1Password; agent exposes eligible keys (no local export needed)
- 1Password SSH agent enabled in app settings; SSH_AUTH_SOCK set in .zprofile
- SSH_AUTH_SOCK export: `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`
- Setup should pause until 1Password SSH agent is enabled (Settings → Developer)
- Dock: hide Recent Applications section (keep only pinned apps). Command: `defaults write com.apple.dock show-recents -bool false && killall Dock`
- Dock: auto-hide. Command: `defaults write com.apple.dock autohide -bool true && killall Dock`
- Dock: magnification on (larger icons on hover). Command: `defaults write com.apple.dock magnification -bool true && defaults write com.apple.dock largesize -int 70 && killall Dock`
- Finder: default to List View. Command: `defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv" && killall Finder`
- Finder: new window target is Home. Command: `defaults write com.apple.finder NewWindowTarget -string "PfHm" && killall Finder`
- Finder: show all filename extensions. Command: `defaults write -g AppleShowAllExtensions -bool true && killall Finder`
- macOS defaults should live in a separate script to run per-user (each account applies its own Dock/Finder prefs)
- User-level tooling (mise/node/pnpm/Codex) should live in a separate script to run per-user
- Keyboard: disable press-and-hold accent popup (enable key repeat). Command: `defaults write -g ApplePressAndHoldEnabled -bool false`
- Keyboard: fast repeat rates. Command: `defaults write -g KeyRepeat -int 2 && defaults write -g InitialKeyRepeat -int 15`
- Shell alias: `alias cy='codex --yolo'` (add to .zshrc)
- Safari: disable password AutoFill/save prompts (use 1Password). Command: `defaults write com.apple.Safari AutoFillPasswords -bool false && killall Safari`

## Proposed order (draft)

- Set machine name (ComputerName/HostName/LocalHostName)
- Install Xcode Command Line Tools
- Install Homebrew and brew bundle
- Install mise + Node LTS, then corepack/pnpm and Codex CLI
- Install 1Password and sign in interactively (for SSH key retrieval)

## Open questions

- What else should always be installed (apps, CLI tools, fonts)?
- Should we manage dotfiles (if so, where)?
- macOS defaults / preferences to set?
- SSH keys / Git config / GPG?
- Editor setup (VS Code, extensions, settings sync)?
- Any work-specific tooling (VPN, 1Password, cloud CLIs)?
- Keep everything in .zprofile, or split between .zprofile and .zshrc?

## Notes

- Current bootstrap steps live in `bootstrap.sh` but may include typos.

## Manual steps

- System Settings → Passwords → AutoFill Passwords and Passkeys: disable (use 1Password)
- Finder: customize sidebar favorites to your liking
- Appearance: set Sidebar icon size to Small (System Settings → Appearance)
- System Settings → Notifications: disable notification sounds per-app (no global toggle)
- Calendar: add Fastmail account (CalDAV) following https://www.fastmail.help/hc/en-us/articles/1500000277682-Automatic-setup-on-Mac
