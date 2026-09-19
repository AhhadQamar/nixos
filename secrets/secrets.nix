let
  licht = "age1w36ahw9vem00k50d0mcpz5eeegqkk9yp93d9zwgl784jss7gjgzsxj8rer";
  recovery = "age1n3mcml8ysrkmwjkkw0ffcqvmrgx2t0ds9nwk5nj586v4thpw2y3s2tdkl4";
  allKeys = [
    licht
    recovery
  ];
in {
  "aria2-rpc-secret.age".publicKeys = allKeys;
  "vaultwarden-admin-token.age".publicKeys = allKeys;
}
