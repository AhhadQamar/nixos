{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.brave = {
    enable = true;
    extensions = [
      # Unhook - Remove YouTube Recommended & Shorts
      {id = "khncfooichmfjbepaaaebmommgaepoid";}
      # Improve YouTube! (for YouTube & Videos)
      {id = "bnomihfieiccainjcjblhegjgglakjdd";}
      # Absolute Enable Right Click & Copy
      {id = "jdocbkpgdakpekjlhemmfcncgdjeiika";}
      # AdBlock — block ads across the web
      {id = "gighmmpiobklfepjocnamgkkbiglidom";}
      # AdBlocker for YouTube™
      {id = "naihbfkjlampnpbnohcehoedklmejhmh";}
      # Aria2 Integration
      {id = "hnenidncmoeebipinjdfniagjnfjbapi";}
      # Behind The Overlay
      {id = "ljipkdpcjbmhkdjjmbbaggebcednbbme";}
      # Browsec VPN - Free VPN Extension
      {id = "omghfjlpggmjjaagoclmmobgdodcjboh";}
      # Grammarly: AI Writing and Grammar Checker App
      {id = "kbfnbcaeplbcioakkpcpgfkobkghlhen";}
      # Privacy Badger
      {id = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp";}
      # React Developer Tools
      {id = "fmkadmapgofadopljbjfkapdkoienihi";}
      # SponsorBlock for YouTube - Skip Sponsorships
      {id = "mnjggcdmjocbbbhaepdhchncahnbgone";}
      # Tap To Tab
      {id = "enhajhmncplakageabmopgpodkdgcodd";}
      # uBlock Origin
      {id = "cjpalhdlnbpafiamejdnhcphjbkeiagm";}
      # Vimium
      {id = "dbepggeogbaibhgnhhndojpepiihcmeb";}
      # Windscribe - Free Proxy and Ad Blocker
      {id = "hnmpcagpplmpfojmgmnngilcnanddlhb";}
    ];
  };
}
