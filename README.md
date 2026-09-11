# nixos

My NixOS flake and home configuration for the `licht` machine.

This repository manages:

- NixOS system configuration
- Home Manager user configuration
- Secret management with `agenix`
- A Hyprland-based desktop setup
- Custom shell, terminal, editor, and theme modules

## Overview

The flake currently defines one NixOS host:

- `licht` — the main machine configuration

It uses:

- `nixpkgs` on the `nixos-26.05` channel
- `home-manager` on the `release-26.05` channel
- `agenix` for encrypted secrets

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

Current secrets include:

- `aria2-rpc-secret.age`
- `qbittorrent-webui-password.age`

The system expects an age identity at:

```bash
/var/lib/agenix/key.txt
```

## Rebuild script

The `rebuild` script formats the config, checks for secrets, rebuilds the system, and commits the new generation:

```bash
./rebuild
```

It runs:

- `alejandra`
- `gitleaks`
- `nh os switch`

## Requirements

To use or adapt this configuration, you will typically need:

- Nix with flakes enabled
- `agenix`
- `home-manager`
- A machine compatible with the `licht` hardware configuration
- Access to the required age identity for secrets

## Notes

- This repo is tailored to the `licht` host.
- The `home-manager` config is imported from `hosts/licht/home.nix`.
- Theme colors are driven by Pywal and propagated into GTK, icon themes, and related components.

## License

No license file is currently present.
