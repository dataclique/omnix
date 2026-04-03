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
    self.nixosModules.disko
    self.nixosModules.base
    {
      omnix.disko.enable = true;
      omnix.base = {
        enable = true;
        sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample example@host" ];
        stateVersion = "25.11";
      };
    }
  ];
}
