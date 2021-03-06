{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dnscache;

  dnscache-root = pkgs.runCommand "dnscache-root" {} ''
    mkdir -p $out/{servers,ip}

    ${concatMapStrings (ip: ''
      echo > "$out/ip/"${lib.escapeShellArg ip}
    '') cfg.clientIps}

    ${concatStrings (mapAttrsToList (host: ips: ''
      ${concatMapStrings (ip: ''
        echo ${lib.escapeShellArg ip} > "$out/servers/"${lib.escapeShellArg host}
      '') ips}
    '') cfg.domainServers)}

    # djbdns contains an outdated list of root servers;
    # if one was not provided in config, provide a current list
    if [ ! -e servers/@ ]; then
      awk '/^.?.ROOT-SERVERS.NET/ { print $4 }' ${pkgs.dns-root-data}/root.hints > $out/servers/@
    fi
  '';

in {

  ###### interface

  options = {
    services.dnscache = {
      enable = mkOption {
        default = false;
        type = types.bool;
        description = "Whether to run the dnscache caching dns server";
      };

      ip = mkOption {
        default = "0.0.0.0";
        type = types.str;
        description = "IP address on which to listen for connections";
      };

      clientIps = mkOption {
        default = [ "127.0.0.1" ];
        type = types.listOf types.str;
        description = "client IP addresses (or prefixes) from which to accept connections";
        example = ["192.168" "172.23.75.82"];
      };

      domainServers = mkOption {
        default = { };
        type = types.attrsOf (types.listOf types.str);
        description = "table of {hostname: server} pairs to use as authoritative servers for hosts (and subhosts)";
        example = {
          "example.com" = ["8.8.8.8" "8.8.4.4"];
        };
      };
    };
  };

  ###### implementation

  config = mkIf config.services.dnscache.enable {
    environment.systemPackages = [ pkgs.djbdns ];
    users.extraUsers.dnscache = {};

    systemd.services.dnscache = {
      description = "djbdns dnscache server";
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ bash daemontools djbdns ];
      preStart = ''
        rm -rf /var/lib/dnscache
        dnscache-conf dnscache dnscache /var/lib/dnscache ${config.services.dnscache.ip}
        rm -rf /var/lib/dnscache/root
        ln -sf ${dnscache-root} /var/lib/dnscache/root
      '';
      script = ''
        cd /var/lib/dnscache/
        exec ./run
      '';
    };
  };
}
