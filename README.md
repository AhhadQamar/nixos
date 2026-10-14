# nixos

NixOS flake for my laptop, **`licht`**: Hyprland desktop, a custom Quickshell shell, Pywal theming, Home Manager, and `agenix` secrets. Everything is declarative and rebuilds with one command.

| | |
| --- | --- |
| **Channel** | `nixos-26.05` + Home Manager `release-26.05` |
| **Host** | `licht` (x86_64, Intel graphics) |
| **User** | `licht` |
| **Desktop** | Hyprland (Lua config) via UWSM, SDDM `pixie` login |
| **Shell** | Quickshell (QML), zsh + starship, kitty, tmux, neovim |
| **Secrets** | `agenix` (keys: `licht` and `recovery`) |
| **Repo path** | `~/nixos` (not `/etc/nixos`) |

**Jump to:** [Install](#install) · [Daily use](#daily-use) · [Key bindings](#key-bindings) · [Customise](#customise) · [Secrets](#secrets) · [Troubleshooting](#troubleshooting) · [Layout](#repository-layout)

---

## Install

### Already running this config?

```bash
cd ~/nixos
./rebuild        # or just: u
```

### Fresh machine

You need: a NixOS installer USB, internet, and the **recovery age key** (private key file, kept off this machine).

**1. Partition and mount** as usual, with the target at `/mnt`.

**2. Clone the repo.** Use HTTPS here: the installer has no SSH key yet.

```bash
mkdir -p /mnt/home/licht
git clone https://github.com/AhhadQamar/nixos.git /mnt/home/licht/nixos
```

**3. Put the age key in place** so `agenix` can decrypt secrets on first boot.

```bash
mkdir -p /mnt/var/lib/agenix
cp /path/to/recovery-key.txt /mnt/var/lib/agenix/key.txt
chmod 600 /mnt/var/lib/agenix/key.txt
```

> Prefer a dedicated key for this machine? See [Add a new machine key](#add-a-new-machine-key).

**4. Generate hardware config.** The committed one belongs to the original laptop.

```bash
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix \
   /mnt/home/licht/nixos/hosts/licht/hardware-configuration.nix
```

Check the disk UUIDs and CPU settings it generated.

**5. Install.**

```bash
nixos-install --root /mnt --flake /mnt/home/licht/nixos#licht
```

**6. Reboot, log in, then finish setup:**

```bash
sudo chown -R licht:users ~/nixos          # repo was cloned as root

# switch the remote to SSH once your key is set up (the rebuild script pushes)
git -C ~/nixos remote set-url origin git@github.com:AhhadQamar/nixos.git

# log out and back in once so NH_FLAKE is set, then:
u
```

**7. Pick a wallpaper** so the theme has colours: press `Super+W`, or run `wal -i <image>`.

### Not the original hardware or user?

This repo is tailored to one laptop. Before the first build on something else, review:

| Item | File |
| --- | --- |
| Username `licht` and home path | `flake.nix`, `hosts/licht/configuration.nix`, `home.nix`, `programs/aria2/config/aria2.conf` |
| Intel-only bits (`iHD`, `intel-media-driver`, `thermald`, microcode) | `system/hardware.nix`, `system/desktop.nix` |
| Monitor names (`eDP-1`, `DP-1`) | `modules/desktop/hypr/config/modules/monitors.lua` (list yours with `hyprctl monitors`) |
| Timezone and keyboard layout | `system/networking.nix` |
| Git name, email, SSH keys | `modules/shell/git/default.nix` |
| Mail accounts and their secrets | `modules/programs/aerc/default.nix`, `secrets/`, `configuration.nix` |

---

## Daily use

All of these need `NH_FLAKE=/home/licht/nixos` (set in `configuration.nix`).

| Command | What it does |
| --- | --- |
| `u` | **Main command.** Format, stage, scan for secrets, `nh os switch`, commit, push |
| `ut` | Activate now without making it the boot default |
| `ub` | Build for next boot only |
| `uu` | Update every flake input, then `u` |
| `nhc` | Garbage-collect old generations |
| `nhs <name>` | Search nixpkgs |
| `i <pkg>` | Try a package in a throwaway shell |
| `rmconf` | Edit `home.nix` |

**What `u` runs** (`./rebuild`), stopping at the first failure:

1. `nix fmt .` (alejandra)
2. `git add -A` (flakes only see tracked files)
3. `gitleaks git --staged`: aborts if it finds a secret
4. `nh os switch`
5. Asks for a commit message: `a` = ask Copilot, `m` or blank = type one, anything else = used as the message. Blank falls back to the generation number
6. Commits (changed files go in the body) and pushes

**Other helpers:** `zshrc`, `hyprconf`, `kittyconf`, `starconf` open that config; `ytm <url>` / `ytal <url>` / `ytms <search>` download music into `~/Music/Artist/Album/`; `ts` is a tmux sessionizer; `y` is yazi with cd-on-exit; `qr`, `cheat`, `json`, `extract`.

**Roll back:** hold `Space` at boot to open the systemd-boot menu (the timeout is 0) and pick an older generation, or use the rollback action in the system updater panel (`Super+U`).

---

## Key bindings

`Super` is the main modifier. Defined in `hypr/config/modules/binds.lua` and `workspaces.lua`.

| Keys | Action |
| --- | --- |
| `Super+Return` | kitty |
| `Super+E` / `B` / `Shift+B` | nautilus / firefox / brave |
| `Super+Q` | close window |
| `Super+h j k l` or arrows | move focus |
| `Super+Shift+arrows` | swap window |
| `Super+Alt+h j k l` | resize |
| `Super+F` / `Shift+F` | fullscreen / maximise |
| `Super+Shift+V` | toggle floating |
| `Super+1..0` | workspace slot on this monitor |
| `Super+Shift+1..0` | send window to slot and follow |
| `Super+Alt+1..0` | slot on the other monitor's block |
| `Super+,` / `.` | focus previous / next monitor |
| `Super+S` / `Shift+S` | scratch workspace / send window there |
| `Super+Shift+T` | drop-down terminal |
| `Super+Shift+L` | lock |
| `Print` / `Shift+Print` | screenshot region / window to clipboard |
| `Super+F12` / `Shift+F12` | save screenshot (screen / region) |

**Quickshell panels:**

| Keys | Panel |
| --- | --- |
| `Super+Space` | launcher |
| `Super+Shift+Space` | Nix package search |
| `Super+V` | clipboard history |
| `Super+A` / `Shift+A` | notifications / do-not-disturb |
| `Super+W` | wallpaper switcher |
| `Super+N` / `Shift+N` | night light panel / on-off |
| `Super+T` | screen time |
| `Super+D` | downloads (aria2) |
| `Super+I` | capture |
| `Super+U` / `Shift+U` | system updates / check now |
| `Super+P`, `Shift+P`, `[`, `]` | music player, play/pause, previous, next |
| `Super+M` | power menu |

Workspaces are per-monitor blocks of 10: the first monitor owns 1..10, the second 11..20. With one screen connected, `Super+Alt+1..0` reaches the second block.

---

## Customise

| I want to… | Edit |
| --- | --- |
| Add a user app | `hosts/licht/home.nix` → `home.packages` |
| Change a system service | `hosts/licht/system/*.nix` |
| Add or change key bindings | `modules/desktop/hypr/config/modules/binds.lua` |
| Change monitors | `monitors.lua` (keep `slots` equal to `slotsPerMonitor` in `quickshell/config/SlotLayout.qml`) |
| Change the bar or panels | `modules/desktop/quickshell/config/*.qml` |
| Edit QML without rebuilding | set `liveReload = true` in `quickshell/default.nix`, rebuild once; saves then reload instantly |
| Change aliases | `modules/shell/zsh/config/.zshrc` (`zshrc`) |
| Change browser extensions | `modules/programs/brave/default.nix` |
| Change the login screen | `system/sddm.nix`, `assets/` |

After any edit: `ut` to test, `u` to keep it.

**Theming:** colours come from Pywal. Changing the wallpaper (`Super+W`) regenerates the palette and updates Quickshell, GTK 3/4, kitty, tmux, hyprlock and Firefox (Pywalfox). Papirus folder icons are recoloured to the same accent by `recolor-icons`.

---

## Secrets

Managed with [`agenix`](https://github.com/ryantm/agenix). Encrypted files live in `secrets/` and are declared in `secrets.nix` and `configuration.nix`.

| Secret | Used by |
| --- | --- |
| `aria2-rpc-secret.age` | `aria2` user service (injected at start) |
| `<account>-gmail.age` (8 files) | `aerc` mail accounts (app passwords) |

Both keys in `secrets.nix` can decrypt everything:

- **`licht`**: this machine, private key at `/var/lib/agenix/key.txt`
- **`recovery`**: backup, private key stored off-machine

`u` runs `gitleaks` on every commit, so a plaintext secret can't be pushed by accident.

### Edit or add a secret

```bash
cd ~/nixos/secrets
agenix -e aria2-rpc-secret.age -i /var/lib/agenix/key.txt
```

For a new secret, add an entry to `secrets.nix` and a matching block in `configuration.nix`.

### Add a new machine key

```bash
age-keygen -o /var/lib/agenix/key.txt     # note the public key it prints
```

Add that public key to `allKeys` in `secrets/secrets.nix`, then re-encrypt with a key that still works (for example `recovery`):

```bash
cd ~/nixos/secrets
agenix -r -i /path/to/recovery-key.txt
```

Commit and push the changed `.age` files.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `u` says `NH_FLAKE is not set` | Log out and back in (`environment.variables` is only read at login) |
| `sudo nixos-rebuild` can't find a config | It defaults to `/etc/nixos`. Use `u`/`ut`/`ub`, or pass `--flake ~/nixos#licht` |
| `u` stops at the gitleaks step | It found something that looks like a secret. Remove it from the staged files, then rerun |
| Build can't see a new file | Flakes ignore untracked files. `u` stages for you; with plain commands run `git add -A` first |
| Bar is blank or uncoloured after install | Run `wal -i <image>` or press `Super+W` and pick a wallpaper |
| Secrets or aria2 fail after first boot | The age key is missing or wrong at `/var/lib/agenix/key.txt` |
| `git push` fails after install | Remote is still HTTPS. Run the `remote set-url` command from [Install](#fresh-machine) step 6 |
| Hyprland errors | `hyprlog` shows the last 50 lines of the log |

---

## Repository layout

```text
flake.nix            inputs and the licht host
flake.lock
rebuild              the script behind `u`
secrets/             agenix files and secrets.nix
hosts/licht/
  configuration.nix  user, secrets, NH_FLAKE
  hardware-configuration.nix
  home.nix           Home Manager entry and user packages
  assets/            avatar and wallpaper for SDDM
  system/            boot, nix, networking, hardware, desktop, sddm, updater
  modules/
    desktop/         hypr, quickshell, pywal, theme, cava, pyprland
    shell/           zsh, starship, fzf, cli-tools, tmux, git, fetch, screentime
    programs/        aerc, aria2, brave, firefox, kitty, mpv, nvim, vscodium, yt-dlp
```

**Notes**

- `mpv` and `nvim` configs are symlinked straight into the repo, so edits there apply without a rebuild.
- `WalColors.qml` inside the Quickshell config is generated at activation and git-ignored.
- GTK 4 / libadwaita ignores theme names, so theming works by overriding named CSS variables in a Pywal template.
- No licence file is present.
