# Minimal: bare DO droplet with SSH access, no services.
# Demonstrates: disko, digitalocean, base, firewall modules.
{ ... }:

{
  omnix.disko.enable = true;
  omnix.digitalocean.enable = true;
  omnix.base = {
    enable = true;
    stateVersion = "25.11";
    sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample" ];
  };
  omnix.firewall.enable = true;
}
