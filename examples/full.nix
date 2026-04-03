{
  self,
  nixpkgs,
  disko,
  ragenix,
}:
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    disko.nixosModules.disko
    ragenix.nixosModules.default
    self.nixosModules.disko
    self.nixosModules.base
    self.nixosModules.digitalocean
    self.nixosModules.storage
    self.nixosModules.firewall
    self.nixosModules.acme
    self.nixosModules.services
    {
      omnix.disko.enable = true;
      omnix.base = {
        enable = true;
        sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample example@host" ];
        stateVersion = "25.11";
      };
      omnix.digitalocean.enable = true;
      omnix.storage = {
        enable = true;
        volumeName = "data-vol";
      };
      omnix.firewall = {
        enable = true;
        enableHTTP = true;
        enableHTTPS = true;
      };
      omnix.acme = {
        enable = true;
        email = "admin@example.com";
      };
      omnix.services = {
        project = "myapp";
        configDir = "/etc/myapp";
        definitions.web = {
          bin = "myapp-web";
          dataDir = "/mnt/data/web";
          logDir = "/var/log/myapp-web";
        };
        definitions.worker = {
          bin = "myapp-worker";
          dataDir = "/mnt/data/worker";
          logDir = "/var/log/myapp-worker";
        };
      };
    }
  ];
}
