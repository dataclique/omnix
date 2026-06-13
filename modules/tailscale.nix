{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.omnix.tailscale;
  tls = cfg.tls;
in
{
  options.omnix.tailscale = {
    enable = lib.mkEnableOption "Tailscale node enrollment";

    authKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "/run/agenix/tailscale-authkey";
      description = ''
        Path to the (decrypted) reusable, tagged Tailscale auth key, used only on
        first enrollment; afterwards tailscaled re-authenticates via the stored
        node key. The consumer is responsible for producing this file (e.g. an
        `age.secrets` entry via ragenix, or any other secrets backend), which
        keeps this module independent of any particular secrets tooling.
      '';
    };

    extraUpFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags for `tailscale up` (e.g. --advertise-routes, --ssh).";
    };

    useRoutingFeatures = lib.mkOption {
      type = lib.types.enum [
        "none"
        "client"
        "server"
        "both"
      ];
      default = "none";
      description = "Enable subnet-router / exit-node routing features (sets IP forwarding).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open UDP 41641 and mark tailscale0 a trusted firewall interface.";
    };

    tls = {
      enable = lib.mkEnableOption "Tailscale-issued HTTPS certificate provisioning (oneshot + daily renewal)";

      magicDnsName = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "MagicDNS FQDN; the cert subject and the cert/key file basename.";
      };

      certDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/tailscale-cert";
        description = "Directory the cert/key are written to.";
      };

      consumer = lib.mkOption {
        type = lib.types.submodule {
          options = {
            user = lib.mkOption {
              type = lib.types.str;
              default = "nginx";
              description = "User that owns the cert files and is granted permitCertUid.";
            };
            group = lib.mkOption {
              type = lib.types.str;
              default = "nginx";
              description = "Group owning the cert directory.";
            };
            reloadUnit = lib.mkOption {
              type = lib.types.str;
              default = "nginx.service";
              description = "Unit reloaded after a cert renewal.";
            };
            beforeUnits = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "nginx.service" ];
              description = "Units ordered after cert provisioning (so the cert exists first).";
            };
          };
        };
        default = { };
        description = "The TLS consumer (defaults target nginx). Decouples the cert machinery from any specific web server.";
      };

      certFile = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        description = "Provisioned certificate path (computed from certDir + magicDnsName); read it from your web-server vhost.";
      };

      keyFile = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        description = "Provisioned private key path (computed from certDir + magicDnsName).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.authKeyFile != "";
        message = "omnix.tailscale.enable requires omnix.tailscale.authKeyFile to be set.";
      }
      {
        assertion = !tls.enable || tls.magicDnsName != "";
        message = "omnix.tailscale.tls.enable requires omnix.tailscale.tls.magicDnsName.";
      }
    ];

    omnix.tailscale.tls.certFile = "${tls.certDir}/${tls.magicDnsName}.crt";
    omnix.tailscale.tls.keyFile = "${tls.certDir}/${tls.magicDnsName}.key";

    services.tailscale = {
      enable = true;
      inherit (cfg) authKeyFile extraUpFlags useRoutingFeatures;
    }
    // lib.optionalAttrs tls.enable { permitCertUid = tls.consumer.user; };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedUDPPorts = [ 41641 ];
      trustedInterfaces = [ "tailscale0" ];
    };

    # Clean up a stale tailscale0 TUN device a previous tailscaled may still
    # hold during activation, so the new unit doesn't crash-loop.
    systemd.services.tailscaled.serviceConfig.ExecStartPre = [
      "-${pkgs.iproute2}/bin/ip link delete tailscale0"
    ];

    systemd.tmpfiles.rules = lib.mkIf tls.enable [
      "d ${tls.certDir} 0750 ${tls.consumer.user} ${tls.consumer.group} -"
    ];

    systemd.services.tailscale-cert = lib.mkIf tls.enable {
      description = "Provision Tailscale HTTPS certificate for ${tls.magicDnsName}";
      after = [ "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
      before = tls.consumer.beforeUnits;
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.tailscale
        pkgs.jq
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = tls.consumer.user;
        Group = tls.consumer.group;
        ExecStartPost = "+${pkgs.bash}/bin/bash -c 'systemctl is-active --quiet ${tls.consumer.reloadUnit} && systemctl reload ${tls.consumer.reloadUnit} || true'";
      };
      script = ''
        set -euo pipefail
        retries=0
        until [ "$(tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null)" = "Running" ]; do
          retries=$((retries + 1))
          if [ "$retries" -ge 30 ]; then
            echo "Tailscale BackendState != Running after 60s" >&2
            exit 1
          fi
          sleep 2
        done
        tailscale cert \
          --cert-file ${tls.certFile} \
          --key-file ${tls.keyFile} \
          ${tls.magicDnsName}
      '';
    };

    systemd.timers.tailscale-cert = lib.mkIf tls.enable {
      description = "Renew Tailscale HTTPS certificate daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
