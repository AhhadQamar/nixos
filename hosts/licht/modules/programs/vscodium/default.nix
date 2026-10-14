{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    vscodium
  ];

  home.file.".config/VSCodium/product.json".text = builtins.toJSON {
    extensionsGallery = {
      serviceUrl = "https://marketplace.visualstudio.com/_apis/public/gallery";
      cacheUrl = "https://vscode.blob.core.windows.net/gallery/index";
      itemUrl = "https://marketplace.visualstudio.com/items";
      controlUrl = "";
    };
  };
}
