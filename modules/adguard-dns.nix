# AdGuard Home DNS Module
# Localhost-only DNS server

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.adguard-home;
in
{
  options.services.adguard-home = {
    enable = mkEnableOption "AdGuard Home DNS server";
    
    bindHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host to bind the DNS server";
    };
    
    port = mkOption {
      type = types.int;
      default = 53;
      description = "Port for DNS server";
    };
    
    webPort = mkOption {
      type = types.int;
      default = 3000;
      description = "Port for web interface";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/adguard-home";
      description = "Directory to store data";
    };
    
    tailscaleInterface = mkOption {
      type = types.bool;
      default = true;
      description = "Also bind to Tailscale interface";
    };
    
    blockLists = mkOption {
      type = types.listOf types.str;
      default = [
        "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
        "https://someonewhocares.org/hosts/zero/hosts"
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
      ];
      description = "List of DNS block lists to use";
    };
    
    upstreamDNS = mkOption {
      type = types.listOf types.str;
      default = [
        "https://dns.cloudflare.com/dns-query"
        "https://dns.google/dns-query"
        "1.1.1.1"
        "8.8.8.8"
      ];
      description = "Upstream DNS servers";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.adguard-home = {
      group = "adguard-home";
      isSystemUser = true;
      home = cfg.dataDir;
      createHome = true;
    };
    
    users.groups.adguard-home = {};
    
    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 adguard-home adguard-home -"
      "d ${cfg.dataDir}/conf 0755 adguard-home adguard-home -"
      "d ${cfg.dataDir}/work 0755 adguard-home adguard-home -"
    ];
    
    # AdGuard Home configuration
    environment.etc."adguard-home/AdGuardHome.yaml".text = ''
      bind_host: ${cfg.bindHost}
      bind_port: ${toString cfg.webPort}
      users:
        - name: admin
          password: $2a$10$c3dLx1lQqGV4YsGGxgqKjO1AQDdVH8J8NxdMQAL1tJgRw8GlwEDqS  # admin
      auth_attempts: 5
      block_auth_min: 15
      http_proxy: ""
      language: en
      theme: auto
      debug_pprof: false
      web_session_ttl: 720
      dns:
        bind_hosts:
          - ${cfg.bindHost}
        port: ${toString cfg.port}
        statistics_interval: 90
        querylog_enabled: true
        querylog_file_enabled: true
        querylog_interval: 2160h
        querylog_size_memory: 1000
        anonymize_client_ip: false
        protection_enabled: true
        blocking_mode: default
        blocking_ipv4: ""
        blocking_ipv6: ""
        blocked_response_ttl: 10
        parental_block_host: family-block.dns.adguard.com
        safebrowsing_block_host: standard-block.dns.adguard.com
        ratelimit: 20
        ratelimit_whitelist: []
        refuse_any: true
        upstream_dns:
          ${concatMapStringsSep "\n          " (dns: "- ${dns}") cfg.upstreamDNS}
        upstream_dns_file: ""
        bootstrap_dns:
          - 9.9.9.10
          - 149.112.112.10
          - 2620:fe::10
          - 2620:fe::fe:10
        all_servers: false
        fastest_addr: false
        fastest_timeout: 1s
        allowed_clients: []
        disallowed_clients: []
        blocked_hosts:
          - version.bind
          - id.server
          - hostname.bind
        trusted_proxies:
          - 127.0.0.0/8
          - ::1/128
        cache_size: 4194304
        cache_ttl_min: 0
        cache_ttl_max: 0
        cache_optimistic: false
        bogus_nxdomain: []
        aaaa_disabled: false
        enable_dnssec: false
        edns_client_subnet:
          custom_ip: ""
          enabled: false
          use_custom: false
        max_goroutines: 300
        handle_ddr: true
        ipset: []
        ipset_file: ""
        filtering_enabled: true
        filters_update_interval: 24
        parental_enabled: false
        safesearch_enabled: false
        safebrowsing_enabled: false
        safebrowsing_cache_size: 1048576
        safesearch_cache_size: 1048576
        parental_cache_size: 1048576
        cache_time: 30
        rewrites: []
        blocked_services: []
        upstream_timeout: 10s
        private_networks: []
        use_private_ptr_resolvers: true
        local_ptr_upstreams: []
        use_dns64: false
        dns64_prefixes: []
        serve_http3: false
        use_http3_upstreams: false
      tls:
        enabled: false
        server_name: ""
        force_https: false
        port_https: 443
        port_dns_over_tls: 853
        port_dns_over_quic: 784
        port_dnscrypt: 0
        dnscrypt_config_file: ""
        allow_unencrypted_doh: false
        certificate_chain: ""
        private_key: ""
        certificate_path: ""
        private_key_path: ""
        strict_sni_check: false
      filters:
        ${concatMapStringsSep "\n        " (url: "- enabled: true\n          url: ${url}\n          name: ${url}\n          id: ${toString (stringLength url)}") cfg.blockLists}
      whitelist_filters: []
      user_rules: []
      dhcp:
        enabled: false
        interface_name: ""
        dhcpv4:
          gateway_ip: ""
          subnet_mask: ""
          range_start: ""
          range_end: ""
          lease_duration: 86400
          icmp_timeout_msec: 1000
          options: []
        dhcpv6:
          range_start: ""
          lease_duration: 86400
          ra_slaac_only: false
          ra_allow_slaac: false
      clients:
        runtime_sources:
          whois: true
          arp: true
          rdns: true
          dhcp: true
          hosts: true
        persistent: []
      log_file: ""
      log_max_backups: 0
      log_max_size: 100
      log_max_age: 3
      log_compress: false
      log_localtime: false
      verbose: false
      os:
        group: ""
        user: ""
        rlimit_nofile: 0
      schema_version: 20
    '';
    
    # AdGuard Home systemd service
    systemd.services.adguard-home = {
      description = "AdGuard Home DNS server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "simple";
        User = "adguard-home";
        Group = "adguard-home";
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${pkgs.adguardhome}/bin/adguardhome -c /etc/adguard-home/AdGuardHome.yaml -w ${cfg.dataDir}/work";
        Restart = "on-failure";
        RestartSec = 10;
        
        # Security settings
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        
        # Capabilities needed for binding to port 53
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
      };
    };
    
    # Open firewall ports
    networking.firewall = {
      allowedTCPPorts = [ cfg.webPort ];
      allowedUDPPorts = [ cfg.port ];
    };
    
    # Create systemd-resolved configuration to use AdGuard Home
    services.resolved = {
      enable = true;
      domains = [ "~." ];
      fallbackDns = [ "${cfg.bindHost}:${toString cfg.port}" ];
      extraConfig = ''
        DNS=${cfg.bindHost}:${toString cfg.port}
        FallbackDNS=1.1.1.1 8.8.8.8
        DNSOverTLS=no
      '';
    };
    
    # Backup configuration
    systemd.services.adguard-home-backup = {
      description = "Backup AdGuard Home configuration";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        # Create backup directory
        mkdir -p /var/backups/adguard-home
        
        # Backup configuration and data
        ${pkgs.rsync}/bin/rsync -av ${cfg.dataDir}/ /var/backups/adguard-home/
        
        # Remove old backups (keep 7 days)
        find /var/backups/adguard-home -name "*.tar.gz" -mtime +7 -delete
        
        # Create compressed backup
        cd /var/backups
        ${pkgs.gnutar}/bin/tar -czf adguard-home/backup-$(date +%Y%m%d-%H%M%S).tar.gz adguard-home/
      '';
    };
    
    systemd.timers.adguard-home-backup = {
      description = "Backup AdGuard Home daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
    
    # Install AdGuard Home
    environment.systemPackages = with pkgs; [
      adguardhome
      dig
      nslookup
    ];
  };
}