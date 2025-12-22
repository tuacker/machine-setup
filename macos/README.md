# macOS setup

Bootstrap script for a fresh macOS install. Installs core tools/apps, configures shell + dev tooling, applies preferred macOS defaults, and prints manual follow-ups at the end.

## Run

```bash
./macos/setup.sh
```

## Options

- Dry run: `./macos/setup.sh --dry-run`
- Only run sections: `./macos/setup.sh --only=brew,apps`
- Skip sections: `./macos/setup.sh --skip=defaults`

### Sections

Groups:
- `global` = `machine`, `xcode`, `brew`, `apps`, `dotnet`
- `user` = `user-shell`, `1password`, `git`, `mise`, `rustup`
- `defaults` = macOS defaults

Steps:
- `machine`, `xcode`, `brew`, `apps`, `dotnet`, `user-shell`, `1password`, `git`, `mise`, `rustup`

`--only` forces the selected sections to run. Dependencies may run automatically.

### Legacy shorthands

`--global-only`, `--user-only`, `--defaults-only`, `--skip-global`, `--skip-user`, `--skip-defaults`

### Logs

Each run creates a new log file in `~/Library/Logs/machine-setup/` named like `YYYYMMDD-HHMMSS-machine-setup.log`.
