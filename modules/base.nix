{ lib, config, pkgs, ... }:

let
  cfg = config.omnix.base;
  shellCfg = cfg.shell;
  isNushell = shellCfg.defaultShell == "nushell";
  isZsh = shellCfg.defaultShell == "zsh";
in {
  options.omnix.base = {
    enable = lib.mkEnableOption "omnix base NixOS settings";

    sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "SSH public keys authorized for root login";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional system packages beyond the base set";
    };

    stateVersion = lib.mkOption {
      type = lib.types.str;
      default = "24.11";
      description = "NixOS state version";
    };

    shell = {
      defaultShell = lib.mkOption {
        type = lib.types.enum [ "bash" "zsh" "nushell" ];
        default = "bash";
        description = ''
          Default interactive shell. Ensures the corresponding shell program
          is enabled at the system level. Use `shellPackage` to set as a
          user's login shell.
        '';
      };

      shellPackage = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "The package for the selected default shell, for use in users.users.<name>.shell";
      };

      bash.viMode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable vi keybindings for interactive bash sessions";
      };

      nushell.manageConfig = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether omnix manages nushell configuration via
          environment.etc. Set to false to manage nushell config
          via home-manager or manually.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };

    users.users.root.openssh.authorizedKeys.keys = cfg.sshKeys;

    nix = {
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
        download-buffer-size = 268435456;
      };

      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };

    omnix.base.shell.shellPackage =
      if isNushell then pkgs.nushell
      else if isZsh then pkgs.zsh
      else pkgs.bash;

    programs.bash.interactiveShellInit =
      lib.mkIf shellCfg.bash.viMode "set -o vi";

    programs.zsh.enable = lib.mkDefault isZsh;

    environment.systemPackages = with pkgs;
      [ bat curl htop rage zellij ]
      ++ lib.optional isNushell pkgs.nushell
      ++ cfg.extraPackages;

    environment.shells = lib.mkIf isNushell [ pkgs.nushell ];

    environment.etc = lib.mkIf (isNushell && shellCfg.nushell.manageConfig) {
      "nushell/config.nu".text = ''
        $env.config = {
          show_banner: false
        }
      '';
      "nushell/env.nu".text = ''
        # omnix managed nushell environment
      '';
    };

    system.activationScripts.per-service-profiles.text =
      "mkdir -p /nix/var/nix/profiles/per-service";

    system.stateVersion = cfg.stateVersion;
  };
}
