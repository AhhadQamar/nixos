# Windscribe VPN, from the community flake `windscribe` (see flake.nix).
# It repacks upstream's own .deb and fixes what NixOS breaks: the root helper
# daemon only runs binaries from /opt/windscribe and hardcodes its PATH, and the
# engine needs the `windscribe` group through a setgid wrapper. The module deals
# with all of that, so the one switch below is enough.
#
# Use it as your normal user, never with sudo:
#   windscribe-cli login
#   windscribe-cli connect
#   windscribe-cli status
#   windscribe-cli disconnect
_: {
  services.windscribe = {
    enable = true;
    # "cli" is the headless engine without the Qt desktop client
    variant = "cli";
    # start the engine with your session, so `windscribe-cli` can reach it
    autoStart = true;
  };
}
