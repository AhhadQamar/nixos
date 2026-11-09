let
  licht = "age1w36ahw9vem00k50d0mcpz5eeegqkk9yp93d9zwgl784jss7gjgzsxj8rer";
  recovery = "age1n3mcml8ysrkmwjkkw0ffcqvmrgx2t0ds9nwk5nj586v4thpw2y3s2tdkl4";
  allKeys = [
    licht
    recovery
  ];
  # wg-licht is read by root (wireguard.nix), so it is not in names.nix.
  names = (import ./names.nix) ++ ["wg-licht"];
in
  builtins.listToAttrs (map (name: {
      name = "${name}.age";
      value.publicKeys = allKeys;
    })
    names)
