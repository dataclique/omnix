{ lib, config, ... }:

let
  cfg = config.omnix.storage;
in
{
  options.omnix.storage = {
    enable = lib.mkEnableOption "DigitalOcean block storage volume mount";

    volumeName = lib.mkOption {
      type = lib.types.str;
      description = "DigitalOcean volume name (used in /dev/disk/by-id/scsi-0DO_Volume_<name>)";
    };

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/data";
      description = "Mount point for the volume";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.match "[A-Za-z0-9._-]+" cfg.volumeName != null;
        message = "omnix.storage.volumeName may only contain letters, digits, '.', '_', '-'. Got: ${cfg.volumeName}";
      }
    ];

    fileSystems.${cfg.mountPoint} = {
      device = "/dev/disk/by-id/scsi-0DO_Volume_${cfg.volumeName}";
      fsType = "ext4";
    };
  };
}
