# Full: multiple services + static sites + ACME + logrotate.
# Demonstrates: every omnix module working together.
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
    volumeName = "full-example-data";
  };
  omnix.services = {
    project = "full-example";
    user = "full-example";
    group = "full-example";
    dynamicUser = false;
    configDir = ./config;
    definitions = {
      api = {
        enabled = true;
        bin = "api-server";
        dataDir = "/mnt/data/api";
        logDir = "/mnt/data/api/logs";
      };
      staging-api = {
        enabled = true;
        bin = "api-server";
        dataDir = "/mnt/data/staging-api";
        logDir = "/mnt/data/staging-api/logs";
      };
      worker = {
        enabled = true;
        bin = "worker";
        dataDir = "/mnt/data/worker";
        logDir = "/mnt/data/worker/logs";
      };
    };
  };
  omnix.staticSites.definitions = {
    prod = {
      port = 80;
      isDefault = true;
      extraLocations = {
        "/api/".proxyPass = "http://127.0.0.1:8000/";
      };
    };
    staging = {
      port = 8080;
      extraLocations = {
        "/api/".proxyPass = "http://127.0.0.1:8001/";
      };
    };
  };
  omnix.firewall = {
    enable = true;
    enableHTTP = true;
    enableHTTPS = true;
    allowedTCPPorts = [ 8080 ];
  };
  omnix.acme = {
    enable = true;
    email = "ops@example.com";
  };
}
