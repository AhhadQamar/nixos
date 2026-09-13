# ╔══════════════════════════════════════════════════════════════╗
# ║                    ZSH POWER USER CONFIG                     ║
# ║                  NixOS · Hyprland · Kitty                    ║
# ╚══════════════════════════════════════════════════════════════╝
#
# ─── ZINIT BOOTSTRAP ────────────────────────────────────────────
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "${ZINIT_HOME}/zinit.zsh"

# ─── PLUGINS ────────────────────────────────────────────────────
# Syntax highlighting — must be LAST among these three
zinit light zsh-users/zsh-syntax-highlighting

# Autosuggestions — grey ghost text from history
zinit light zsh-users/zsh-autosuggestions

# Extra completions (docker, cargo, npm, git, and more)
zinit light zsh-users/zsh-completions

# fzf-tab — fuzzy Tab completion (needs fzf, provided via Nix)
zinit light Aloxaf/fzf-tab

# ─── HISTORY ────────────────────────────────────────────────────
HISTSIZE=50000
SAVEHIST=50000
HISTFILE="$HOME/.zsh_history"

setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt HIST_VERIFY

# ─── COMPLETION SYSTEM ──────────────────────────────────────────
autoload -Uz compinit
# Only rebuild + audit the completion dump once every 24h.
# On every other launch, just trust the cached dump (-C skips
# the fpath scan/compaudit entirely) — this is what's costing
# ~1.5s per shell right now.
zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${zcompdump:h}"
if [[ -n ${zcompdump}(#qN.mh+24) ]]; then
    compinit -d "$zcompdump"
else
    compinit -C -d "$zcompdump"
fi

{ zcompile "$zcompdump" } &!


zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no

zstyle ':fzf-tab:complete:cd:*' fzf-preview \
  'eza --tree --level=2 --color=always $realpath 2>/dev/null || ls $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview \
  'eza --tree --level=2 --color=always $realpath 2>/dev/null || ls $realpath'

# ─── KEY BINDINGS ───────────────────────────────────────────────
bindkey -e

bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^H' backward-kill-word
bindkey '^[[3;5~' kill-word
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# ─── STARSHIP PROMPT ────────────────────────────────────────────
eval "$(starship init zsh)"

# ─── ZOXIDE ─────────────────────────────────────────────────────
eval "$(zoxide init --cmd cd zsh)"

# ─── FZF ────────────────────────────────────────────────────────
# Nix's fzf package ships its own zsh integration; if home-manager's
# programs.fzf.enableZshIntegration handles sourcing for you, these
# two lines are redundant but harmless to leave commented for reference.
# source "${pkgs.fzf}/share/fzf/key-bindings.zsh"
# source "${pkgs.fzf}/share/fzf/completion.zsh"

export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

export FZF_DEFAULT_OPTS='
  --height 40%
  --layout=reverse
  --border=rounded
  --info=inline
  --preview-window=right:55%:wrap
  --bind=ctrl-d:half-page-down,ctrl-u:half-page-up
'

# ─── ENVIRONMENT VARIABLES ──────────────────────────────────────
# EDITOR/VISUAL/BROWSER/PAGER and PATH entries are set declaratively
# in default.nix via home.sessionVariables / home.sessionPath, so
# they're intentionally not duplicated here.

# ─── ALIASES — NAVIGATION ───────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'

# ─── ALIASES — EZA (modern ls) ──────────────────────────────────
alias ls='eza --color=always --group-directories-first --icons'
alias ll='eza -la --color=always --group-directories-first --icons --git'
alias la='eza -a --color=always --group-directories-first --icons'
alias lt='eza --tree --level=2 --color=always --icons'
alias llt='eza --tree --level=3 --color=always --icons -la'

# ─── ALIASES — BAT (modern cat) ─────────────────────────────────
alias cat='bat --style=numbers,changes'
alias catp='bat --plain'

# ─── ALIASES — NIX ───────────────────────────────────────────────
# nh takes a plain path to the flake dir and auto-detects the hostname
# (matches against $(hostname), which is "licht" here) — no "#licht"
# needed, which is good because zsh's EXTENDED_GLOB treats a bare '#'
# as a glob operator and mangles it anyway.
# NH_FLAKE itself is set declaratively in configuration.nix (environment.variables),
# not here — same convention as EDITOR/VISUAL.

alias u='nh os switch && rb'      # rebuild + switch now
alias ub='nh os boot'       # build for next boot, don't switch now
alias ut='nh os test'       # activate temporarily, don't persist to boot
alias uu='nix flake update --flake "$NH_FLAKE" && u && rb'   # bump all inputs, then rebuild
alias nhc='nh clean all'    # gc old generations
alias nhs='nh search'       # package search
alias rb='/etc/nixos/rebuild'
# 'i' = try a package in a throwaway shell (does NOT persist — nothing
# to uninstall after, just exit the shell). Closest thing to `pacman -S`
# for "let me just try this" without touching your config.
i() { nix shell "nixpkgs#$1"; }

# no real 'pacr' equivalent exists — removing a package means deleting
# it from home.nix/configuration.nix and rebuilding. This just jumps
# you to the file so it's a one-command habit instead of two.
rmconf() { $EDITOR /etc/nixos/hosts/licht/home.nix }

# ─── ALIASES — GIT ──────────────────────────────────────────────
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -m'
alias gca='git commit --amend'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate --all'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull'
alias gs='git status -sb'
alias gst='git stash'
alias grb='git rebase'
alias gri='git rebase -i'

# ─── ALIASES — SYSTEM ───────────────────────────────────────────
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias ps='ps auxf'
alias top='btop'
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv'
alias ln='ln -iv'

# Quick config edits
alias zshrc='$EDITOR /etc/nixos/hosts/licht/modules/zsh/config/.zshrc'
alias zshrcs='source ~/.zshrc'
alias hyprconf='$EDITOR ~/.config/hypr/'
alias kittyconf='$EDITOR ~/.config/kitty/kitty.conf'
alias starconf='$EDITOR ~/.config/starship.toml'

# Hyprland helpers
alias hyprlog='cat /tmp/hypr/*.log | tail -50'

# ─── ALIASES — NETWORK ──────────────────────────────────────────
alias myip='curl -s ifconfig.me && echo'
alias localip="ip route get 1 | awk '{print \$7; exit}'"
alias ping='ping -c 5'
alias wget='wget -c'

# ─── ALIASES — MISC ─────────────────────────────────────────────
alias q='exit'
alias clr='clear'
alias c='clear'
alias hist='history | fzf'
alias ports='ss -tulnp'
alias path='echo -e ${PATH//:/\\n}'

# ─── ALIASES — OTHER ─────────────────────────────────────────────
alias anime='anipy-cli'
alias calc='daisy'
alias ytd='yt-dlp'

# ─── FUNCTIONS ──────────────────────────────────────────────────

mkcd() {
    mkdir -p "$1" && cd "$1"
}

extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"    ;;
            *.tar.gz)    tar xzf "$1"    ;;
            *.tar.xz)    tar xJf "$1"    ;;
            *.tar.zst)   tar --zstd -xf "$1" ;;
            *.bz2)       bunzip2 "$1"    ;;
            *.gz)        gunzip "$1"     ;;
            *.tar)       tar xf "$1"     ;;
            *.tbz2)      tar xjf "$1"    ;;
            *.tgz)       tar xzf "$1"    ;;
            *.zip)       unzip "$1"      ;;
            *.Z)         uncompress "$1" ;;
            *.7z)        7z x "$1"       ;;
            *.zst)       unzstd "$1"     ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

fcd() {
    local dir
    dir=$(find "${1:-.}" -type d 2>/dev/null | fzf +m) && cd "$dir"
}

fkill() {
    local pid
    pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
    if [ -n "$pid" ]; then
        echo "$pid" | xargs kill -"${1:-9}"
    fi
}

sesh() {
    local host
    host=$(grep '^Host ' ~/.ssh/config | awk '{print $2}' | fzf)
    [ -n "$host" ] && ssh "$host"
}

gitignore() {
    curl -sL "https://www.toptal.com/developers/gitignore/api/$*"
}

backup() {
    cp "$1" "${1}.bak.$(date +%Y%m%d_%H%M%S)"
}

sysinfo() {
    echo "── System ──────────────────────────────"
    uname -a
    echo "── CPU ─────────────────────────────────"
    grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs
    echo "── Memory ──────────────────────────────"
    free -h
    echo "── Disk ────────────────────────────────"
    df -h /
    echo "── Uptime ──────────────────────────────"
    uptime -p
}

say() {
    edge-tts --voice en-US-AriaNeural --file "$1" --write-media /dev/stdout | mpv -
}

# Yazi shell wrapper — cd into last dir on exit
function y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    command yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd < "$tmp"
    [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
    \rm -f -- "$tmp" >/dev/null 2>&1
}
gh() { command gh "$@" }

recolor-icons() {
  local colors_file="$HOME/.cache/wal/colors"
  if [ ! -s "$colors_file" ]; then
    echo "No wal colors found — run 'wal -i <wallpaper>' first."
    return 1
  fi

  local accent
  accent=$(awk 'NR==5' "$colors_file")
  accent="${accent#\#}"
  local hexr="${accent:0:2}" hexg="${accent:2:2}" hexb="${accent:4:2}"
  local r=$((16#$hexr))
  local g=$((16#$hexg))
  local b=$((16#$hexb))

  declare -A presets=(
    [black]="30 30 30"     [blue]="26 128 196"   [bluegrey]="96 125 139"
    [brown]="93 64 55"     [cyan]="0 172 193"    [green]="76 175 80"
    [grey]="158 158 158"   [magenta]="216 27 96" [orange]="245 124 0"
    [red]="211 47 47"      [teal]="0 121 107"    [violet]="123 31 162"
    [yellow]="251 192 45"
  )

  local best="grey" bestDist=999999
  for name in "${(@k)presets}"; do
    read -r pr pg pb <<< "${presets[$name]}"
    local dr=$((r-pr)) dg=$((g-pg)) db=$((b-pb))
    local dist=$((dr*dr + dg*dg + db*db))
    if [ "$dist" -lt "$bestDist" ]; then bestDist=$dist; best=$name; fi
  done

  echo "Nearest preset: $best"
  papirus-folders -C "$best" --theme Papirus
  gtk-update-icon-cache -f "$HOME/.local/share/icons/Papirus" 2>/dev/null
  gtk-update-icon-cache -f "$HOME/.local/share/icons/Papirus-Dark" 2>/dev/null
  pkill nautilus 2>/dev/null
  echo "Done — reopen Files to see it."
}
# ─── AUTOSUGGESTIONS TWEAKS ─────────────────────────────────────
bindkey '^ ' autosuggest-accept
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=true
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# ─── SYNTAX HIGHLIGHTING TWEAKS ─────────────────────────────────
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)
typeset -A ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=cyan,bold'
ZSH_HIGHLIGHT_STYLES[alias]='fg=cyan,bold'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=cyan,bold'
ZSH_HIGHLIGHT_STYLES[function]='fg=cyan,bold'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red,bold'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=yellow'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=yellow'
ZSH_HIGHLIGHT_STYLES[path]='fg=green'
ZSH_HIGHLIGHT_STYLES[comment]='fg=8'
ZSH_HIGHLIGHT_STYLES[option]='fg=magenta'

# ─── MISCELLANEOUS OPTIONS ──────────────────────────────────────
setopt AUTO_CD
setopt CORRECT
setopt GLOB_DOTS
setopt EXTENDED_GLOB
setopt NO_BEEP
setopt INTERACTIVE_COMMENTS

# ─── LESS / MAN COLORS ──────────────────────────────────────────
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# ─── KITTY INTEGRATION ──────────────────────────────────────────
if [ -n "$KITTY_INSTALLATION_DIR" ]; then
    export KITTY_SHELL_INTEGRATION="enabled"
    autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
    kitty-integration
    unfunction kitty-integration
fi

# Terminal window title = current directory
precmd() {
    print -Pn "\e]0;%~\a"
}

# ─── LOCAL OVERRIDES ────────────────────────────────────────────
# Machine-specific / secret config, not tracked in the flake repo
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
