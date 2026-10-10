{pkgs, ...}: {
  home.packages = [
    (pkgs.writeShellScriptBin "screentime" ''
      exec ${pkgs.python3}/bin/python3 ${./screentime.py} "$@"
    '')
  ];
}
