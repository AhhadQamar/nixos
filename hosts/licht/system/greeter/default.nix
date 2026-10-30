# The Quickshell login screen: greetd + cage + Quickshell. It is the only login
# path (imported by configuration.nix); there is no display manager besides it.
#
# How it fits together: greetd starts cage as the `greeter` user. Cage is a
# kiosk compositor: it shows one fullscreen app and nothing else, with no
# animations, keybinds or banners, and it exits when that app does. The app is
# the launcher below, which builds the greeter's Quickshell config folder and
# starts Quickshell on it. The greeter (Greeter.qml) asks greetd to log you in;
# when that works it hands greetd your real session and exits, and cage goes
# with it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  user = "licht";
  # The big clock on the login screen: 12 hour with AM/PM (true) or 24 hour.
  # Keep it in step with clock12h in quickshell/config/Config.qml, which does
  # the same for the screen lock.
  clock12h = true;
  home = config.users.users.${user}.home;

  # What the greeter shares with the shell: the same tokens, colours, controls
  # and the whole design of the lock, so the login screen and the screen lock
  # never drift apart. Every file here must come with everything it uses
  # (LockStage needs the buttons, the field and the glass, for one): QML only
  # finds a component that sits in the same folder, and a missing one stops
  # the whole greeter from loading.
  shellDir = ../../modules/desktop/quickshell/config;
  shared = [
    # Tokens and primitives
    "Style.qml"
    "Colors.qml"
    "Icons.qml"
    "Txt.qml"
    # Controls (they need only Style, Colors, Txt and Icons; KeyCap draws the key hints)
    "IconButton.qml"
    "TextButton.qml"
    "SearchField.qml"
    "KeyCap.qml"
    # Glass (Style and Colors)
    "EdgeLight.qml"
    "StageShade.qml"
    # The lock's design: the state and motion (LockModel) and the look
    # (LockStage), shared with Lock.qml
    "LockModel.qml"
    "LockStage.qml"
  ];

  greeterConfig = pkgs.linkFarm "qs-greeter-config" (
    [
      {
        name = "shell.qml";
        path = ./shell.qml;
      }
      {
        name = "Greeter.qml";
        path = ./Greeter.qml;
      }
    ]
    ++ map (f: {
      name = f;
      path = shellDir + "/${f}";
    })
    shared
  );

  # Used when the greeter may not read your palette (see the ACLs below)
  fallbackColors = ../../modules/desktop/quickshell/WalColors.fallback.qml;

  # Starts Hyprland directly (no UWSM); the greeter hands it to greetd.
  # start-hyprland is the wrapper Hyprland itself recommends. systemd-cat sends
  # what it prints to the journal, not to the console, so the screen stays
  # clean while your session starts: journalctl -b -t hyprland
  sessionCmd = "${pkgs.systemd}/bin/systemd-cat -t hyprland ${config.programs.hyprland.package}/bin/start-hyprland";

  # Builds a throwaway config folder (the shared files plus a palette) and
  # runs Quickshell on it. The palette is your current one when the greeter
  # can read it, and a fixed one otherwise: without that choice, an unreadable
  # palette would mean a blank login screen.
  launcher = pkgs.writeShellScript "qs-greeter" ''
    set -u
    dir=$(${pkgs.coreutils}/bin/mktemp -d)
    ${pkgs.coreutils}/bin/ln -s ${greeterConfig}/* "$dir"/
    palette=${home}/.cache/wal/colors.qml
    if [ -r "$palette" ]; then
      ${pkgs.coreutils}/bin/ln -s "$palette" "$dir/WalColors.qml"
    else
      ${pkgs.coreutils}/bin/ln -s ${fallbackColors} "$dir/WalColors.qml"
    fi
    # Qt draws its own title bar and corners on a window when the compositor
    # does not: cage has none, so tell Qt not to
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    export GREETER_USER=${user}
    export GREETER_CLOCK12H=${
      if clock12h
      then "1"
      else "0"
    }
    # What the screen shows behind the clock. Only passed on when readable,
    # so a missing file means a plain backdrop, never a broken screen.
    wall=${home}/Pictures/Wallpapers/.current_wallpaper
    [ -r "$wall" ] && export GREETER_WALLPAPER="$wall"
    export GREETER_SESSION="${sessionCmd}"
    exec ${lib.getExe pkgs.quickshell} -p "$dir"
  '';
in {
  services.greetd = {
    enable = true;
    settings.default_session = {
      user = "greeter";
      # -d: no window decorations; -s lets Ctrl+Alt+F-keys switch to a TTY (the
      # way out if the greeter ever breaks); -m last shows it on one screen
      # only, the last one cage finds. Cage shows a single fullscreen window
      # and cannot draw the shell's layer-shell windows, so the greeter is one
      # ordinary window.
      # systemd-cat keeps everything cage and the greeter print out of the
      # console. It is in the journal instead: journalctl -b -t greeter
      command = "${pkgs.systemd}/bin/systemd-cat -t greeter ${lib.getExe pkgs.cage} -d -s -m last -- ${launcher}";
    };
  };

  # The keyring is unlocked by the login, as it was with SDDM
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Let the greeter user read your palette and wallpaper: it may
  # step through these folders to a file whose path it knows, but not list
  # them. The files themselves are normally world-readable already.
  systemd.tmpfiles.rules =
    [
      # The home folder is 0700, which leaves its ACL mask at ---, and the mask
      # cancels the greeter's x. So the mask is set to --x here, and only
      # here: on the other folders (0755) a --x mask would take the group's
      # read permission away.
      "a+ ${home} - - - - u:greeter:--x,m::--x"
    ]
    ++ map (d: "a+ ${d} - - - - u:greeter:--x") [
      "${home}/.cache"
      "${home}/.cache/wal"
      "${home}/Pictures"
      "${home}/Pictures/Wallpapers"
    ];
}
