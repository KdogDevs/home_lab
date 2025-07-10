# Nginx Proxy Manager Module
# Localhost UI, public 80/443 reverse-proxy

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nginx-proxy-manager;
in
{
  options.services.nginx-proxy-manager = {
    enable = mkEnableOption "Nginx Proxy Manager";
    
    adminPort = mkOption {
      type = types.int;
      default = 81;
      description = "Port for the admin interface";
    };
    
    httpPort = mkOption {
      type = types.int;
      default = 80;
      description = "Port for HTTP traffic";
    };
    
    httpsPort = mkOption {
      type = types.int;
      default = 443;
      description = "Port for HTTPS traffic";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/nginx-proxy-manager";
      description = "Directory to store data";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports";
    };
  };

  config = mkIf cfg.enable {
    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/data 0755 root root -"
      "d ${cfg.dataDir}/letsencrypt 0755 root root -"
    ];
    
    # Docker container for Nginx Proxy Manager
    virtualisation.docker.enable = true;
    
    systemd.services.nginx-proxy-manager = {
      description = "Nginx Proxy Manager";
      after = [ "docker.service" "network.target" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = [
          "${pkgs.docker}/bin/docker pull jc21/nginx-proxy-manager:latest"
          "${pkgs.docker}/bin/docker stop nginx-proxy-manager || true"
          "${pkgs.docker}/bin/docker rm nginx-proxy-manager || true"
        ];
        ExecStart = ''
          ${pkgs.docker}/bin/docker run -d \
            --name nginx-proxy-manager \
            --restart unless-stopped \
            -p ${toString cfg.httpPort}:80 \
            -p ${toString cfg.httpsPort}:443 \
            -p ${toString cfg.adminPort}:81 \
            -v ${cfg.dataDir}/data:/data \
            -v ${cfg.dataDir}/letsencrypt:/etc/letsencrypt \
            -e DISABLE_IPV6=true \
            jc21/nginx-proxy-manager:latest
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop nginx-proxy-manager";
        ExecStopPost = "${pkgs.docker}/bin/docker rm nginx-proxy-manager";
      };
    };
    
    # Open firewall ports
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.httpPort cfg.httpsPort cfg.adminPort ];
    };
    
    # Backup configuration
    systemd.services.nginx-proxy-manager-backup = {
      description = "Backup Nginx Proxy Manager configuration";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        # Create backup directory
        mkdir -p /var/backups/nginx-proxy-manager
        
        # Backup data directory
        ${pkgs.rsync}/bin/rsync -av ${cfg.dataDir}/ /var/backups/nginx-proxy-manager/
        
        # Remove old backups (keep 7 days)
        find /var/backups/nginx-proxy-manager -name "*.tar.gz" -mtime +7 -delete
        
        # Create compressed backup
        cd /var/backups
        ${pkgs.gnutar}/bin/tar -czf nginx-proxy-manager/backup-$(date +%Y%m%d-%H%M%S).tar.gz nginx-proxy-manager/
      '';
    };
    
    systemd.timers.nginx-proxy-manager-backup = {
      description = "Backup Nginx Proxy Manager daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
    
    # Health check service
    systemd.services.nginx-proxy-manager-health = {
      description = "Health check for Nginx Proxy Manager";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        # Check if container is running
        if ! ${pkgs.docker}/bin/docker ps | grep -q nginx-proxy-manager; then
          echo "Nginx Proxy Manager container is not running, restarting..."
          systemctl restart nginx-proxy-manager
        fi
        
        # Check if admin interface is accessible
        if ! ${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.adminPort} >/dev/null 2>&1; then
          echo "Admin interface is not accessible, restarting..."
          systemctl restart nginx-proxy-manager
        fi
      '';
    };
    
    systemd.timers.nginx-proxy-manager-health = {
      description = "Health check for Nginx Proxy Manager every 5 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/5";
        Persistent = true;
      };
    };
    
    # Log rotation for docker logs
    services.logrotate.settings.docker = {
      files = "/var/lib/docker/containers/*/*-json.log";
      frequency = "daily";
      rotate = 7;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
    };
    
    # Install useful tools
    environment.systemPackages = with pkgs; [
      docker-compose
      curl
      jq
    ];
  };
}