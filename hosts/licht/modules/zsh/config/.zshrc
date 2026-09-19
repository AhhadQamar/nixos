
# ─── HISTORY ────────────────────────────────────────────────────
HISTSIZE=50000
SAVEHIST=50000
HISTFILE="$HOME/.zsh_history"

setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt HIST_VERIFY

# ─── COMPLETION STYLES ──────────────────────────────────────────
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

alias u='"$NH_FLAKE"/rebuild'  # format, scan for secrets, switch, commit, push
alias ub='nh os boot'       # build for next boot, don't switch now
alias ut='nh os test'       # activate temporarily, don't persist to boot
alias uu='nix flake update --flake "$NH_FLAKE" && u'    # bump all inputs, then rebuild
alias nhc='nh clean all'    # gc old generations
alias nhs='nh search'       # package search
# 'i' = try a package in a throwaway shell (does NOT persist — nothing
# to uninstall after, just exit the shell). Closest thing to `pacman -S`
# for "let me just try this" without touching your config.
i() { nix shell "nixpkgs#$1"; }

rmconf() { $EDITOR $HOME/nixos/hosts/licht/home.nix }

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
alias dus='du -sh'   # don't shadow `du`; `du -sh *` would become `du -sh -sh *`
alias free='free -h'
alias psa='ps auxf'  # don't shadow `ps`; it would break `ps -p <pid>`
alias top='btop'
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv'
alias ln='ln -iv'

# Quick config edits
alias zshrc='$EDITOR $HOME/nixos/hosts/licht/modules/zsh/config/.zshrc'
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

# Terminal QR code. `qr "https://..."` or pipe something in, e.g.
# `qr "WIFI:T:WPA;S:myssid;P:mypassword;;"` to hand a guest a scannable
# Wi-Fi code instead of reading the password out loud.
qr() {
    if [ -n "$1" ]; then
        qrencode -t ANSIUTF8 "$1"
    else
        qrencode -t ANSIUTF8 < /dev/stdin
    fi
}

# Quick weather. No args = auto-detected by IP; `weather lahore` for a city.
# https:// is explicit and not optional here -- curl's scheme-guessing
# defaults to plain http for a hostname like "wttr.in" that doesn't start
# with a recognized prefix (ftp., smtp., ...), so leaving the scheme off
# would send this in cleartext.
weather() {
    curl -s "https://wttr.in/${1:-}"
}

# Serve $PWD over the LAN, e.g. to grab a file on your phone.
# Binds only to the detected LAN address, not every interface -- python's
# http.server defaults to 0.0.0.0, which would also answer on a VPN/Tailscale
# tunnel or public wifi, not just the LAN you have in mind. If the address
# can't be detected, this refuses rather than silently falling back to
# exposing every interface.
serve() {
    local port="${1:-8000}"
    local ip
    ip=$(localip 2>/dev/null)
    if [ -z "$ip" ]; then
        echo "Could not detect a LAN address -- refusing to bind to all interfaces."
        echo "Bind one explicitly if you're sure: python3 -m http.server $port --bind <ip>"
        return 1
    fi
    echo "Serving $PWD on http://$ip:$port  (Ctrl-C to stop)"
    python3 -m http.server "$port" --bind "$ip"
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

# ─── SECURITY / GENERATORS ──────────────────────────────────────

# Random password. Charset avoids quotes, backslashes, `$`, `;`, `|`, `<`, `>`
# on purpose -- those are the characters most likely to break something when
# the result gets pasted into a URL, a shell, or a config file.
genpass() {
    local len="${1:-20}"
    # The trailing "-" is a literal hyphen only because it's the LAST char in
    # this set; anywhere else, tr reads "x-y" as a range. "+-=" earlier here
    # was a real bug (a hidden range covering , . / : ; < too) caught by
    # testing this against real output rather than just reading the line.
    LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*()_+=-' < /dev/urandom | head -c "$len"
    echo
}

# Numeric PIN, e.g. for a phone lock code or a 2FA-adjacent form.
genpin() {
    local len="${1:-6}"
    LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c "$len"
    echo
}

# Clipboard variants of genpass/genpin, for when you don't want the secret
# ever hitting the screen.
#
# The complication: autostart.lua runs `wl-paste --watch cliphist store`,
# which writes EVERY clipboard change to cliphist's on-disk history --
# unconditionally. cliphist has no built-in way to exclude sensitive content
# (a patch for the x-kde-passwordManagerHint convention that KeePassXC etc.
# use was proposed upstream and never merged), so there's no clean "don't
# record this one" signal to give it.
#
# So this does what `pass` does instead:
#   1. Put the value on the clipboard.
#   2. Race cliphist's watcher to scrub the entry back out of its history.
#      This is a genuine race, not a guarantee -- if the watcher wins, the
#      entry sits in cliphist until you delete it yourself (open the
#      clipboard manager and remove that one entry, or `cliphist wipe` for
#      everything).
#   3. After 45s, clear the clipboard -- but only if it still holds exactly
#      what we put there, so this never wipes something you copied since.
_clip_then_scrub() {
    local val="$1"
    printf '%s' "$val" | wl-copy
    (
        sleep 0.3
        cliphist delete-query -- "$val" >/dev/null 2>&1
    ) &!
    (
        sleep 45
        [ "$(wl-paste -n 2>/dev/null)" = "$val" ] && wl-copy --clear
    ) &!
}

genpassc() {
    local val
    val=$(genpass "$@")
    _clip_then_scrub "$val"
    echo "password copied -- clears in 45s if untouched"
}

genpinc() {
    local val
    val=$(genpin "$@")
    _clip_then_scrub "$val"
    echo "PIN copied -- clears in 45s if untouched"
}

# ─── ALIASES — HANDY EXTRAS ─────────────────────────────────────
alias cheat='tldr'          # quick, example-first man pages
alias json='jq .'           # pretty-print JSON: curl ... | json
# `dust` and `ncdu` are left unaliased (see `dus` above for why) -- run them
# directly: `dust` for a du-style tree, `ncdu` for an interactive browser.

# ─── AUTOSUGGESTIONS TWEAKS ─────────────────────────────────────
bindkey '^ ' autosuggest-accept
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
# strategy + async are set via programs.zsh.autosuggestion in default.nix

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

