let
  licht = "age1w36ahw9vem00k50d0mcpz5eeegqkk9yp93d9zwgl784jss7gjgzsxj8rer";
  recovery = "age1k9amgryg7slkmgsjdqhgxqdahrj7gezgtyr9e4gfdz4asxpfqyzq0qeqmf";
  allKeys = [
    licht
    recovery
  ];
  names = import ./names.nix;
in
  builtins.listToAttrs (map (name: {
      name = "${name}.age";
      value.publicKeys = allKeys;
    })
    names)
