{
  pkgs,
  osConfig,
  ...
}: {
  accounts.email.accounts = {
    ahhadqamar1 = {
      primary = true;
      address = "ahhadqamar1@gmail.com";
      userName = "ahhadqamar1@gmail.com";
      realName = "Ahhad Qamar";
      flavor = "gmail.com";
      passwordCommand = "cat ${osConfig.age.secrets.ahhadqamar1-gmail.path}";
      aerc.enable = true;
    };

    ahadqam1 = {
      address = "ahadqam1@gmail.com";
      userName = "ahadqam1@gmail.com";
      realName = "Ahhad Qamar";
      flavor = "gmail.com";
      passwordCommand = "cat ${osConfig.age.secrets.ahadqam1-gmail.path}";
      aerc.enable = true;
    };

    ahhad067 = {
      address = "ahhad067@gmail.com";
      userName = "ahhad067@gmail.com";
      realName = "Ahhad Qamar";
      flavor = "gmail.com";
      passwordCommand = "cat ${osConfig.age.secrets.ahhad067-gmail.path}";
      aerc.enable = true;
    };
    ahhadqamar3154 = {
      address = "ahhadqamar3154@gmail.com";
      userName = "ahhadqamar3154@gmail.com";
      realName = "Ahhad Qamar";
      flavor = "gmail.com";
      passwordCommand = "cat ${osConfig.age.secrets.ahhadqamar3154-gmail.path}";
      aerc.enable = true;
    };
    ahhad3309 = {
      address = "ahhad3309@gmail.com";
      userName = "ahhad3309@gmail.com";
      realName = "Ahhad Qamar";
      flavor = "gmail.com";
      passwordCommand = "cat ${osConfig.age.secrets.ahhad3309-gmail.path}";
      aerc.enable = true;
    };
    gamerking3154 = {
      address = "gamerking3154@gmail.com";
      userName = "gamerking3154@gmail.com";
      realName = "Ahhad Qamar";
      flavor = "gmail.com";
      passwordCommand = "cat ${osConfig.age.secrets.gamerking3154-gmail.path}";
      aerc.enable = true;
    };
    msahhad78 = {
      address = "msahhad78@gmail.com";
      userName = "msahhad78@gmail.com";
      realName = "Ahhad Qamar";
      flavor = "gmail.com";
      passwordCommand = "cat ${osConfig.age.secrets.msahhad78-gmail.path}";
      aerc.enable = true;
    };
    ahhadqamara = {
      address = "ahhadqamara@gmail.com";
      userName = "ahhadqamara@gmail.com";
      realName = "Ahhad Qamar";
      flavor = "gmail.com";
      passwordCommand = "cat ${osConfig.age.secrets.ahhadqamara-gmail.path}";
      aerc.enable = true;
    };
  };
  programs.aerc = {
    enable = true;
    extraConfig = {
      general.unsafe-accounts-conf = true;

      filters = {
        "text/plain" = "colorize";
        "text/calendar" = "calendar";
        "text/html" = "${pkgs.w3m}/bin/w3m -I UTF-8 -T text/html -dump";
      };
      hooks.mail-received = ''notify-send "[$AERC_ACCOUNT/$AERC_FOLDER] New mail from $AERC_FROM_NAME" "$AERC_SUBJECT"'';
    };
  };
}
