# nixos

My NixOS flake and home configuration for the `licht` machine.

This repository manages:

- NixOS system configuration
- Home Manager user configuration
- Secret management with `agenix`
- A Hyprland-based desktop setup
- Custom shell, terminal, editor, and theme modules

## Contents

- [Overview](#overview)
- [Installation](#installation)
- [Features](#features)
- [Repository structure](#repository-structure)
- [Secrets](#secrets)
- [Rebuild script](#rebuild-script)
- [Useful aliases](#useful-aliases)
- [Requirements](#requirements)
- [Notes](#notes)

## Overview

The flake currently defines one NixOS host:

- `licht` — the main machine configuration

It uses:

- `nixpkgs` on the `nixos-26.05` channel
- `home-manager` on the `release-26.05` channel
- `agenix` for encrypted secrets

## Installation

### Fresh install (new machine)

1. **Boot the installer**, partition and format the disk as usual,
   then mount your target filesystems under `/mnt`.

2. **Clone this repo** into place. `/mnt/home/licht` doesn't exist as a
   real home directory yet at this point (user creation happens during
   activation below), so create the parent first:

```bash
   mkdir -p /mnt/home/licht
   git clone git@github.com:AhhadQamar/nixos.git /mnt/home/licht/nixos
```

3. **Provide a private key for `agenix` before the first rebuild.**
   The secrets in `secrets/` (`aria2-rpc-secret.age`,
   `qbittorrent-webui-password.age`) are encrypted against two age
   public keys — `licht` and `recovery` — defined in
   `secrets/secrets.nix`. Activation reads
   `age.identityPaths = ["/var/lib/agenix/key.txt"]` from
   `configuration.nix` and needs a matching private key at that exact
   path, or the build will fail partway through trying to decrypt
   secrets it has no key for. Pick one:

   **Option A — reuse the recovery key** (fastest for a one-off reinstall):

```bash
   mkdir -p /mnt/var/lib/agenix
   cp /path/to/recovery-key.txt /mnt/var/lib/agenix/key.txt
```

Since `recovery` is already an authorized decryptor in
`secrets.nix`, this works immediately with no further changes.

**Option B — generate a dedicated key for this machine** (better
hygiene if this becomes a second permanent host):

```bash
   age-keygen -o /mnt/var/lib/agenix/key.txt
```

Note the public key it prints, add it to `secrets/secrets.nix`'s
`allKeys` list, then re-encrypt the existing secrets so the new key
is actually authorized to decrypt them (run using whichever key
_currently_ works, e.g. the recovery key, to open and re-save each
one):

```bash
   agenix -e aria2-rpc-secret.age
   agenix -e qbittorrent-webui-password.age
```

Commit and push the updated `secrets.nix` and the re-encrypted `.age` files.

4. **Generate hardware config for the new machine** — the existing
   `hosts/licht/hardware-configuration.nix` is specific to the
   original machine's disks/drivers and won't work elsewhere as-is:

```bash
   nixos-generate-config --root /mnt
   cp /mnt/etc/nixos/hardware-configuration.nix /mnt/home/licht/nixos/hosts/licht/hardware-configuration.nix
```

Review it — disk device paths, filesystem UUIDs, and CPU microcode
settings will differ from the original.

5. **Install:**

```bash
   nixos-install --root /mnt --flake /mnt/home/licht/nixos#licht
```

With the key already in place from step 3, secret decryption during
activation succeeds and the build completes cleanly.

6. **Reboot, log in, and fix ownership.** The repo was cloned as root
   before the `licht` user existed, so `useradd` won't have taken
   ownership of it on its own:

```bash
   sudo chown -R licht:users ~/nixos
```

Then switch to the normal workflow below.

### Existing, already-installed system

```bash
cd ~/nixos
./rebuild
```

or just `u`, which runs the same script.
Requires `NH_FLAKE=/home/licht/nixos`, already declared in
`configuration.nix`. That variable is set via `environment.variables`,
which is only re-sourced at login — after changing it, log out and
back in (not just open a new terminal) before `u` will resolve to the
new path.

## Features

### System

- systemd-boot
- NetworkManager
- zram swap
- daily Nix store optimisation and garbage collection
- Intel graphics acceleration
- PipeWire audio
- XDG portals for Hyprland
- `nix-ld` enabled for running unwrapped binaries

### Desktop

- Hyprland
- Hyprlock / Hypridle
- Pyprland
- Quickshell
- Pywal-based theming
- GTK, Qt, and icon theme integration

### User environment

- `zsh`
- `kitty`
- `neovim`
- `vscodium`
- `yazi`
- `firefox`
- `brave`
- `btop`
- `vesktop`
- `playerctl`
- `nautilus`

### Utilities

- `aria2`
- `qBittorrent`
- `yt-dlp`
- `udiskie` automount
- custom wallpaper and theme helpers

## Repository structure

```text
flake.nix
hosts/
  licht/
    configuration.nix
    hardware-configuration.nix
    home.nix
    modules/
      aria2/
      cava/
      fetch/
      git/
      hypr/
      kitty/
      nvim/
      pyprland/
      pywal/
      qbittorrent/
      quickshell/
      theme/
      vscodium/
      yt-dlp/
      zsh/
secrets/
rebuild
```

## Secrets

Encrypted secrets are managed with `agenix` and stored in `secrets/`.

Current secrets:

- `aria2-rpc-secret.age`
- `qbittorrent-webui-password.age`

Both are encrypted against two age public keys, defined in
`secrets/secrets.nix`:

- `licht` — this machine's identity, private key at `/var/lib/agenix/key.txt`
- `recovery` — a backup identity, private key kept off this machine

See [Installation](#installation) for how these keys come into play on
a fresh install.

## Rebuild script

The `rebuild` script formats the config, checks for secrets, rebuilds the system, and commits the new generation:

```bash
./rebuild
```

It runs, in order:

1. `alejandra` — formats all `.nix` files
2. `gitleaks detect` — scans for accidentally-committed secrets before anything is pushed
3. `nh os switch` — rebuilds and activates
4. Prompts for a commit message (falls back to the NixOS generation number if left blank), attaches the list of changed files as the commit body, then pushes

## Useful aliases

Defined in the `zsh` module (`.zshrc`):

| Alias           | What it does                                                  |
| --------------- | ------------------------------------------------------------- |
| `u`             | runs `./rebuild` — format, scan, `nh os switch`, commit, push |
| `ub`            | `nh os boot` — build for next boot only                       |
| `ut`            | `nh os test` — activate now, don't persist to boot            |
| `uu`            | update all flake inputs, then rebuild                         |
| `nhc`           | `nh clean all` — garbage collect old generations              |
| `nhs`           | `nh search` — search nixpkgs                                  |
| `i <pkg>`       | try a package in a throwaway shell, nothing persists          |
| `rmconf`        | jump straight to `home.nix` for editing                       |
| `recolor-icons` | re-match Papirus folder colors to the current wal palette     |

All of these rely on `NH_FLAKE=/home/licht/nixos`, set declaratively in `configuration.nix`.

## Requirements

- Nix with flakes enabled
- Access to a valid age identity for secrets (see [Secrets](#secrets))
- A machine compatible with the `licht` hardware configuration (or a
  freshly generated one — see [Installation](#installation))

## Notes

- This repo lives at `/home/licht/nixos`, not `/etc/nixos`. `/etc/nixos`
  is left absent — nothing in this repo hardcodes it, everything reads
  `NH_FLAKE` instead — but `sudo nixos-rebuild` without `--flake`
  defaults to `/etc/nixos` and will fail if run out of habit; use the
  `u`/`ub`/`ut` aliases or pass `--flake ~/nixos#licht` explicitly.
- This repo is tailored to the `licht` host.
- The `home-manager` config is imported from `hosts/licht/home.nix`.
- Theme colors are driven by Pywal and propagated into GTK, icon
  themes, and related components.
- GTK4/libadwaita theming works by overriding named CSS variables
  (`@accent_bg_color`, `sidebar_bg_color`, etc.) in a pywal-generated
  template — libadwaita ignores classic GTK theme names, so this is
  the only reliable way to theme apps like Nautilus.
- Folder icon colors (Papirus) are matched to the same accent-picking
  logic used by the Quickshell bar (`Colors.qml`'s saturation/brightness
  scoring), via the `recolor-icons` script and a build-time activation
  step — not a live symlink, since `papirus-folders` needs a writable
  theme copy outside the Nix store.

## License

No license file is currently present.
