# Single service: one backend behind nginx with block storage.
# Demonstrates: all basic modules + services + storage.
{ ... }:

{
  omnix.disko.enable = true;
  omnix.digitalocean.enable = true;
  omnix.base = {
    enable = true;
    stateVersion = "25.11";
    sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample" ];
  };
  omnix.storage = {
    enable = true;
    volumeName = "example-data";
  };
  omnix.services = {
    project = "example";
    configDir = ./config;
    definitions = {
      api = {
        enabled = true;
        bin = "example-api";
        dataDir = "/mnt/data/api";
      };
    };
  };
  omnix.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 ];
  };

  services.nginx = {
    enable = true;
    virtualHosts.default = {
      default = true;
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
      ];
      locations."/".proxyPass = "http://127.0.0.1:8000";
    };
  };
}
