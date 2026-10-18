{pkgs, ...}: {
  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  hardware.graphics = {
    enable = true;

    extraPackages = with pkgs; [
      intel-media-driver
    ];
  };

  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;
  services.fwupd.enable = true;

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  boot.kernel.sysctl = {
    "vm.swappiness" = 100;
    "vm.page-cluster" = 0;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4096;
    }
  ];

  services.fstrim.enable = true;
}
