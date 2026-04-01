{ nixos-anywhere }:

{
  pkgs,
  keysFile,
  configName,
  system,
  ragenixPkg ? null,
  secretsRules ? null,
}:

let
  shell = import ./shell.nix { inherit keysFile; };

in
pkgs.writeShellApplication {
  name = "bootstrap-nixos";
  runtimeInputs = [
    pkgs.rage
    pkgs.jq
    pkgs.gnused
    pkgs.openssh
    nixos-anywhere.packages.${system}.default
  ]
  ++ (if ragenixPkg != null then [ ragenixPkg ] else [ ]);
  text = ''
    ${shell.resolveIp}
    ssh_opts=(-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$identity")

    nixos-anywhere --flake ".#${configName}" \
      --option pure-eval false \
      --ssh-option "IdentityFile=$identity" \
      --target-host "root@$host_ip" "$@"

    echo "Waiting for host to come back up..."
    retries=0
    until ssh "''${ssh_opts[@]}" "root@$host_ip" true 2>/dev/null; do
      retries=$((retries + 1))
      if [ "$retries" -ge 60 ]; then
        echo "Host did not come back up after 5 minutes" >&2
        exit 1
      fi
      sleep 5
    done

    new_key=$(
      ssh "''${ssh_opts[@]}" "root@$host_ip" \
        cat /etc/ssh/ssh_host_ed25519_key.pub \
        | awk '{print $1 " " $2}'
    )

    sed -i -z \
      's|host =\n      "ssh-ed25519 [^"]*";|host =\n      "'"$new_key"'";|' \
      keys.nix

    if ! grep -q "$new_key" keys.nix; then
      echo "ERROR: host key replacement in keys.nix failed" >&2
      exit 1
    fi

    echo "Updated host key in keys.nix"
    ${
      if ragenixPkg != null && secretsRules != null then
        ''
          echo "Rekeying secrets..."
          ragenix --rules ${secretsRules} -i "$identity" -r
        ''
      else
        ""
    }
  '';
}
