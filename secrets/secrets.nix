let
  licht = "age1w36ahw9vem00k50d0mcpz5eeegqkk9yp93d9zwgl784jss7gjgzsxj8rer";
  recovery = "age1k9amgryg7slkmgsjdqhgxqdahrj7gezgtyr9e4gfdz4asxpfqyzq0qeqmf";
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
