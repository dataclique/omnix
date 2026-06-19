# omnix

Composable Nix infrastructure for DigitalOcean deployments. Provides NixOS
modules, library functions, and flake templates for provisioning, deploying, and
managing services on DigitalOcean with terraform, deploy-rs, and age-encrypted
secrets.

## Quick Start

```bash
mkdir my-service && cd my-service
nix flake init -t github:dataclique/omnix#do-service
# Fill in keys.nix with your SSH public keys
# Set up terraform: nix run .#tfEditVars
# Provision: nix run .#tfInit && nix run .#tfPlan && nix run .#tfApply
# Bootstrap NixOS: nix run .#bootstrap
# Deploy: nix run .#deployAll
```

## Modules

Each module is independently usable under the `omnix.*` namespace:

| Module         | Option prefix           | Purpose                                       |
| -------------- | ----------------------- | --------------------------------------------- |
| `disko`        | `omnix.disko.*`         | GPT disk layout (boot + EFI + root)           |
| `digitalocean` | `omnix.digitalocean.*`  | Cloud-init, QEMU guest, GRUB EFI              |
| `base`         | `omnix.base.*`          | SSH hardening, nix GC, flakes, base packages  |
| `storage`      | `omnix.storage.*`       | DO block storage volume mount                 |
| `services`     | `omnix.services.*`      | Systemd service generation with marker files  |
| `staticSites`  | `omnix.staticSites.*`   | Nginx vhosts via symlink swap (no rebuild)     |
| `firewall`     | `omnix.firewall.*`      | TCP port allowlist (SSH always included)       |
| `acme`         | `omnix.acme.*`          | Let's Encrypt TLS certificates                |

`omnix.nixosModules.default` imports all omnix modules plus upstream disko and
ragenix modules. For most projects this is all you need.

### Static Sites

Static sites (frontends, docs) are deployed independently from the NixOS system
config. Nginx points at stable symlink paths (`/var/lib/sites/<name>`), and
deploy-rs profiles swap the symlink to the new build then reload nginx. This
means:

- System deploys never rebuild nginx config for frontend changes
- Prod and staging can serve different frontend builds
- Frontend deploys are fast (symlink swap + nginx reload, no system activation)

```nix
# os.nix -- NixOS config (sets up nginx, never changes for frontend updates)
omnix.staticSites.definitions = {
  prod = {
    port = 80;
    isDefault = true;
    extraLocations = {
      "/api/" = { proxyPass = "http://127.0.0.1:8000/"; };
    };
  };
  staging = {
    port = 8080;
    extraLocations = {
      "/api/" = { proxyPass = "http://127.0.0.1:8001/"; };
    };
  };
};

# flake.nix -- deploy config (tells deploy-rs which package to deploy)
deployConfig = omnix.lib.mkDeploy {
  inherit self services;
  nodeName = "my-service";
  package = self.packages.x86_64-linux.my-service;
  staticSites = {
    prod = { enabled = true; package = self.packages.x86_64-linux.frontend; };
    staging = { enabled = true; package = self.packages.x86_64-linux.frontend; };
  };
};
```

Deploy a specific frontend: `nix run .#deployService -- prod`

### Services

Backend services use the same deploy-rs profile pattern but with systemd
services instead of symlinks. Each service gets:

- A systemd unit that only starts via deploy-rs (marker file gate)
- A per-service nix profile at `/nix/var/nix/profiles/per-service/<name>`
- Automatic tmpfiles rules for data and log directories
- Optional logrotate configuration

```nix
# os.nix
omnix.services = {
  project = "my-service";
  user = "my-service";
  group = "my-group";
  dynamicUser = false;
  configDir = ./config;
  definitions = {
    my-service = {
      enabled = true;
      bin = "my-service";
      dataDir = "/mnt/data/prod";
      logDir = "/mnt/data/prod/logs";
    };
  };
};
```

## Library Functions

| Function          | Purpose                                                                   |
| ----------------- | ------------------------------------------------------------------------- |
| `lib.mkTerraform` | Terraform wrapper scripts (init, plan, apply, rekey, remote SSH, etc.)    |
| `lib.mkDeploy`    | deploy-rs config + shell wrappers (deployNixos, deployService, deployAll) |
| `lib.mkBootstrap` | nixos-anywhere provisioning + host key update                             |
| `lib.mkGitHooks`  | Pre-commit hooks (nixfmt, deadnix, taplo, optional rustfmt)               |

### mkDeploy

Generates deploy-rs node config and CLI wrappers. Supports both backend
services and static sites.

```nix
deployConfig = omnix.lib.mkDeploy {
  inherit self;
  nodeName = "my-service";           # deploy-rs node name
  services = import ./services.nix;  # backend service definitions
  package = self.packages.x86_64-linux.my-service;  # backend binary package

  # Optional: static sites deployed via symlink swap
  staticSites = {
    prod = { enabled = true; package = self.packages.x86_64-linux.frontend; };
  };

  # Optional: override target architecture (default: x86_64-linux)
  targetSystem = "x86_64-linux";
};

# Use the config
deploy = deployConfig.config;

# Get CLI wrappers
deployPkgs = deployConfig.wrappers {
  inherit pkgs infraPkgs;
  localSystem = system;
};
# deployPkgs.deployNixos, deployPkgs.deployService, deployPkgs.deployAll
```

### mkTerraform

Generates terraform wrapper scripts with age-encrypted state and variables.
All scripts accept `-i <identity>` for the SSH key used to decrypt.

```nix
infraPkgs = omnix.lib.mkTerraform {
  inherit pkgs system;
  keysFile = ./keys.nix;                    # keys + roles for encryption
  ragenixPkg = omnix.inputs.ragenix.packages.${system}.default;  # optional
  secretsRules = ./config/secrets.nix;      # optional, for ragenix rekey
};
# infraPkgs.tfInit, tfPlan, tfApply, tfDestroy, tfImport, tfEditVars, tfRekey
# infraPkgs.rekey, remote, resolveIp
```

## Using as a Flake Input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    omnix.url = "github:dataclique/omnix";
    omnix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, omnix, nixpkgs, ... }: {
    nixosConfigurations.myservice = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        omnix.nixosModules.default
        ./os.nix
      ];
    };
  };
}
```

The consumer owns its nixpkgs pin and makes omnix follow it -- not the other
way around.

See [SPEC.md](./SPEC.md) for design details and [ROADMAP.md](./ROADMAP.md) for
planned work.
