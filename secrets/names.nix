# Secrets that user licht reads (mail passwords, aria2 token).
# Both hosts/licht/configuration.nix (decrypts them at boot) and secrets.nix
# (the keys the agenix command encrypts to) read this list, so a name only
# needs adding here. Then: agenix -e secrets/<name>.age
[
  "aria2-rpc-secret"
  "ahhadqamar1-gmail"
  "ahadqam1-gmail"
  "ahhad067-gmail"
  "ahhadqamar3154-gmail"
  "ahhad3309-gmail"
  "gamerking3154-gmail"
  "msahhad78-gmail"
  "ahhadqamara-gmail"
]
