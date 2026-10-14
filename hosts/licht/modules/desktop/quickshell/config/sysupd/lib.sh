# Shared by the sysupd scripts: `. "$(dirname "$0")/lib.sh"`.

# Root work goes through one script that lives in the system closure
# (hosts/licht/system/updater.nix). /etc/sysupd/root-helper points at it.
# Sets $helper, or stops the script with exit 4 when it is not installed.
require_helper() {
  helper=$(readlink -f /etc/sysupd/root-helper 2>/dev/null || true)
  if [ -z "$helper" ] || [ ! -x "$helper" ]; then
    echo "The root helper is not installed. Add ./system/updater.nix to the imports in"
    echo "hosts/licht/configuration.nix and rebuild once (u), then try again."
    exit 4
  fi
}

# Old generations of your own profiles (nix-env, nix profile). Best effort: a
# profile that does not exist is fine. With an argument it keeps that many days.
# home-manager needs nothing here: it is part of the system generation.
user_profile_cleanup() {
  if [ -n "${1:-}" ]; then
    nix-env --delete-generations "${1}d" >/dev/null 2>&1 || true
    nix profile wipe-history --older-than "${1}d" >/dev/null 2>&1 || true
  else
    nix-env --delete-generations old >/dev/null 2>&1 || true
    nix profile wipe-history >/dev/null 2>&1 || true
  fi
}
