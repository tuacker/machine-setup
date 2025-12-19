xcode-select --install

// waited for gui install of xcode-select finished

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo 'eval $(/opt/homebrew/bin/brew shellenv)' >> $HOME/.zprofile

// created ~/Brewfile with just brew "git" and brew "mise" in it for now

mise use -g node@lts

echo 'eval "$(mise activate zsh)"' >> .zprofile

// so far probably some shell reloads missing to pick up .zprofile changes which i did by reopening terminal

corepack enable
corepack prepare pnpm@latest --activate

pnpm setup
pnpm add -g @openai/codex

// should i use .zshrc for everything or .zprofile? pnpm for example created the .zshrc file now...
// also i may have typos in the commands listed in this file as i just typed them out instead of copy paste in here
