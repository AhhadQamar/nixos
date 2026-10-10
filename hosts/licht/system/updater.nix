# Root side of the Quickshell system updater (modules/desktop/quickshell/config/sysupd).
#
# The panel builds as your own user. Only the last step needs root (switching,
# changing the boot entry, deleting generations), and it goes through one small
# script that lives in the system closure. That has three upsides over running
# a shell snippet through pkexec:
#   - the password prompt says what is happening instead of "bash"
#   - the script is immutable (it cannot be edited from your home directory) and
#     checks every argument before acting
#   - it runs inside a transient system unit, so reloading Quickshell cannot cut
#     a switch off half way
{
  config,
  lib,
  pkgs,
  ...
}: let
  helper = pkgs.writeShellScript "sysupd-root" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [config.nix.package pkgs.coreutils pkgs.systemd]}

    profile=/nix/var/nix/profiles/system

    die() { echo "sysupd: $*" >&2; exit 1; }
    is_num() { case "$1" in "" | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

    # Re-run inside a transient system unit, the way nixos-rebuild does
    if [ "''${1:-}" != "--in-unit" ]; then
      exec systemd-run --collect --pipe --quiet --service-type=exec --unit=sysupd-root -- "$0" --in-unit "$@"
    fi
    shift

    [ "$#" -ge 1 ] || die "no command given"
    cmd=$1
    shift

    # Only a real, unmodified system closure from the store
    check_closure() {
      case "$1" in
        /nix/store/*-nixos-system-*) ;;
        *) die "not a system closure: $1" ;;
      esac
      [ -d "$1" ] && [ "$(readlink -f "$1")" = "$1" ] || die "not a plain store path: $1"
      [ -x "$1/bin/switch-to-configuration" ] || die "no switch-to-configuration in $1"
    }

    current_id() {
      local l
      l=$(readlink "$profile")
      l=''${l#system-}
      echo "''${l%-link}"
    }

    case "$cmd" in
      # activate <switch|test|boot> <closure>
      activate)
        [ "$#" -eq 2 ] || die "usage: activate <switch|test|boot> <closure>"
        mode=$1
        closure=$2
        case "$mode" in switch | test | boot) ;; *) die "bad mode: $mode" ;; esac
        check_closure "$closure"
        # test activates without touching the profile, so the boot default stays
        if [ "$mode" != test ]; then
          nix-env -p "$profile" --set "$closure"
        fi
        exec "$closure/bin/switch-to-configuration" "$mode"
        ;;

      # rollback <generation>
      rollback)
        [ "$#" -eq 1 ] || die "usage: rollback <generation>"
        is_num "$1" || die "bad generation: $1"
        [ -e "$profile-$1-link" ] || die "generation $1 does not exist"
        nix-env -p "$profile" --switch-generation "$1"
        exec "$profile/bin/switch-to-configuration" switch
        ;;

      # clean all | clean <generation> | clean old <days>
      clean)
        [ "$#" -ge 1 ] || die "usage: clean all | <generation> | old <days>"
        case "$1" in
          all)
            nix-env -p "$profile" --delete-generations old
            ;;
          old)
            [ "$#" -eq 2 ] || die "usage: clean old <days>"
            is_num "$2" || die "bad age: $2"
            nix-env -p "$profile" --delete-generations "''${2}d"
            ;;
          *)
            is_num "$1" || die "bad generation: $1"
            [ -e "$profile-$1-link" ] || die "generation $1 does not exist"
            [ "$1" != "$(current_id)" ] || die "refusing to delete the current generation"
            nix-env -p "$profile" --delete-generations "$1"
            ;;
        esac
        nix-collect-garbage
        # Rebuild the boot menu so it stops listing what was just deleted
        "$profile/bin/switch-to-configuration" boot
        ;;

      *)
        die "unknown command: $cmd"
        ;;
    esac
  '';

  policy = pkgs.writeTextDir "share/polkit-1/actions/org.licht.sysupd.policy" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
    <policyconfig>
      <vendor>licht</vendor>
      <action id="org.licht.sysupd.run">
        <description>Change the installed system</description>
        <message>Authentication is required to switch the system, change the boot entry or delete generations</message>
        <defaults>
          <allow_any>no</allow_any>
          <allow_inactive>no</allow_inactive>
          <allow_active>auth_admin_keep</allow_active>
        </defaults>
        <annotate key="org.freedesktop.policykit.exec.path">${helper}</annotate>
      </action>
    </policyconfig>
  '';
in {
  # The panel finds the helper here, so it needs no store path of its own
  environment.etc."sysupd/root-helper".source = helper;
  environment.systemPackages = [policy];
}
