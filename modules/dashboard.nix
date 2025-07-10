# Dashboard Module
# Central UI + REST ingestion for fleet management

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.homelab-dashboard;
in
{
  options.services.homelab-dashboard = {
    enable = mkEnableOption "Home Lab Dashboard";
    
    port = mkOption {
      type = types.int;
      default = 3000;
      description = "Port for the dashboard web interface";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/homelab-dashboard";
      description = "Directory to store dashboard data";
    };
    
    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to bind the dashboard";
    };
    
    allowedOrigins = mkOption {
      type = types.listOf types.str;
      default = [ "localhost" "127.0.0.1" ];
      description = "Allowed origins for CORS";
    };
    
    collectInterval = mkOption {
      type = types.int;
      default = 300;
      description = "Interval in seconds to collect metrics from nodes";
    };
    
    retentionDays = mkOption {
      type = types.int;
      default = 30;
      description = "Number of days to retain metrics data";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.homelab-dashboard = {
      group = "homelab-dashboard";
      isSystemUser = true;
      home = cfg.dataDir;
      createHome = true;
    };
    
    users.groups.homelab-dashboard = {};
    
    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 homelab-dashboard homelab-dashboard -"
      "d ${cfg.dataDir}/db 0755 homelab-dashboard homelab-dashboard -"
      "d ${cfg.dataDir}/logs 0755 homelab-dashboard homelab-dashboard -"
    ];
    
    # Dashboard application
    environment.etc."homelab-dashboard/config.json".text = builtins.toJSON {
      server = {
        host = cfg.bindAddress;
        port = cfg.port;
        cors_origins = cfg.allowedOrigins;
      };
      database = {
        path = "${cfg.dataDir}/db/dashboard.db";
      };
      collection = {
        interval = cfg.collectInterval;
        retention_days = cfg.retentionDays;
      };
      logging = {
        level = "info";
        file = "${cfg.dataDir}/logs/dashboard.log";
      };
    };
    
    # Dashboard service using Docker
    virtualisation.docker.enable = true;
    
    # Create the dashboard application
    systemd.services.homelab-dashboard = {
      description = "Home Lab Dashboard";
      after = [ "docker.service" "network.target" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        ExecStartPre = [
          "${pkgs.docker}/bin/docker pull grafana/grafana:latest"
          "${pkgs.docker}/bin/docker pull prom/prometheus:latest"
          "${pkgs.docker}/bin/docker stop homelab-grafana homelab-prometheus || true"
          "${pkgs.docker}/bin/docker rm homelab-grafana homelab-prometheus || true"
          # Create network
          "${pkgs.docker}/bin/docker network create homelab || true"
        ];
        ExecStart = let
          prometheusConfig = pkgs.writeText "prometheus.yml" ''
            global:
              scrape_interval: 15s
              evaluation_interval: 15s
            
            rule_files:
              # - "first_rules.yml"
              # - "second_rules.yml"
            
            scrape_configs:
              - job_name: 'prometheus'
                static_configs:
                  - targets: ['localhost:9090']
              
              - job_name: 'node-exporter'
                static_configs:
                  - targets: 
                    - 'host.docker.internal:9100'  # Control node
                    # Add slave nodes here as they're discovered
                scrape_interval: 30s
                metrics_path: /metrics
              
              - job_name: 'dashboard-api'
                static_configs:
                  - targets: ['homelab-dashboard:8080']
                scrape_interval: 60s
          '';
          
          grafanaConfig = pkgs.writeText "grafana.ini" ''
            [server]
            http_addr = 0.0.0.0
            http_port = 3000
            
            [security]
            admin_user = admin
            admin_password = admin
            
            [analytics]
            reporting_enabled = false
            check_for_updates = false
            
            [snapshots]
            external_enabled = false
            
            [users]
            allow_sign_up = false
            allow_org_create = false
            auto_assign_org = true
            auto_assign_org_id = 1
            auto_assign_org_role = Viewer
            
            [auth.anonymous]
            enabled = true
            org_name = Main Org.
            org_role = Viewer
            
            [dashboards]
            default_home_dashboard_path = /var/lib/grafana/dashboards/homelab.json
          '';
          
        in ''
          # Start Prometheus
          ${pkgs.docker}/bin/docker run -d \
            --name homelab-prometheus \
            --network homelab \
            --restart unless-stopped \
            -p 9090:9090 \
            -v ${prometheusConfig}:/etc/prometheus/prometheus.yml \
            -v ${cfg.dataDir}/prometheus:/prometheus \
            prom/prometheus:latest \
            --config.file=/etc/prometheus/prometheus.yml \
            --storage.tsdb.path=/prometheus \
            --web.console.libraries=/usr/share/prometheus/console_libraries \
            --web.console.templates=/usr/share/prometheus/consoles \
            --web.enable-lifecycle
          
          # Start Grafana
          ${pkgs.docker}/bin/docker run -d \
            --name homelab-grafana \
            --network homelab \
            --restart unless-stopped \
            -p ${toString cfg.port}:3000 \
            -v ${grafanaConfig}:/etc/grafana/grafana.ini \
            -v ${cfg.dataDir}/grafana:/var/lib/grafana \
            -e GF_PATHS_CONFIG=/etc/grafana/grafana.ini \
            grafana/grafana:latest
        '';
        ExecStop = ''
          ${pkgs.docker}/bin/docker stop homelab-grafana homelab-prometheus || true
        '';
        ExecStopPost = ''
          ${pkgs.docker}/bin/docker rm homelab-grafana homelab-prometheus || true
        '';
      };
    };
    
    # REST API for collecting metrics
    systemd.services.homelab-dashboard-api = {
      description = "Home Lab Dashboard API";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "simple";
        User = "homelab-dashboard";
        Group = "homelab-dashboard";
        WorkingDirectory = cfg.dataDir;
        ExecStart = let
          dashboardScript = pkgs.writeScript "dashboard-api.py" ''
            #!/usr/bin/env python3
            import json
            import sqlite3
            import time
            import threading
            from datetime import datetime, timedelta
            from http.server import HTTPServer, BaseHTTPRequestHandler
            from urllib.parse import urlparse, parse_qs
            
            class DashboardHandler(BaseHTTPRequestHandler):
                def do_GET(self):
                    parsed_path = urlparse(self.path)
                    
                    if parsed_path.path == '/health':
                        self.send_response(200)
                        self.send_header('Content-type', 'application/json')
                        self.end_headers()
                        self.wfile.write(json.dumps({"status": "ok", "timestamp": time.time()}).encode())
                    
                    elif parsed_path.path == '/metrics':
                        self.send_response(200)
                        self.send_header('Content-type', 'application/json')
                        self.end_headers()
                        
                        # Query recent metrics from database
                        conn = sqlite3.connect('${cfg.dataDir}/db/dashboard.db')
                        cursor = conn.cursor()
                        cursor.execute('''
                            SELECT hostname, data, timestamp FROM node_metrics 
                            WHERE timestamp > ? ORDER BY timestamp DESC LIMIT 100
                        ''', (time.time() - 3600,))  # Last hour
                        
                        metrics = []
                        for row in cursor.fetchall():
                            metrics.append({
                                'hostname': row[0],
                                'data': json.loads(row[1]),
                                'timestamp': row[2]
                            })
                        
                        conn.close()
                        self.wfile.write(json.dumps(metrics).encode())
                    
                    else:
                        self.send_response(404)
                        self.end_headers()
                
                def do_POST(self):
                    parsed_path = urlparse(self.path)
                    
                    if parsed_path.path == '/api/metrics':
                        content_length = int(self.headers['Content-Length'])
                        post_data = self.rfile.read(content_length)
                        
                        try:
                            data = json.loads(post_data.decode('utf-8'))
                            hostname = data.get('hostname', 'unknown')
                            metrics = data.get('metrics', {})
                            
                            # Store in database
                            conn = sqlite3.connect('${cfg.dataDir}/db/dashboard.db')
                            cursor = conn.cursor()
                            cursor.execute('''
                                INSERT INTO node_metrics (hostname, data, timestamp)
                                VALUES (?, ?, ?)
                            ''', (hostname, json.dumps(metrics), time.time()))
                            conn.commit()
                            conn.close()
                            
                            self.send_response(200)
                            self.send_header('Content-type', 'application/json')
                            self.end_headers()
                            self.wfile.write(json.dumps({"status": "ok"}).encode())
                            
                        except Exception as e:
                            self.send_response(400)
                            self.send_header('Content-type', 'application/json')
                            self.end_headers()
                            self.wfile.write(json.dumps({"error": str(e)}).encode())
                    
                    else:
                        self.send_response(404)
                        self.end_headers()
            
            def init_database():
                conn = sqlite3.connect('${cfg.dataDir}/db/dashboard.db')
                cursor = conn.cursor()
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS node_metrics (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        hostname TEXT NOT NULL,
                        data TEXT NOT NULL,
                        timestamp REAL NOT NULL
                    )
                ''')
                cursor.execute('''
                    CREATE INDEX IF NOT EXISTS idx_hostname_timestamp 
                    ON node_metrics(hostname, timestamp)
                ''')
                conn.commit()
                conn.close()
            
            def cleanup_old_data():
                while True:
                    conn = sqlite3.connect('${cfg.dataDir}/db/dashboard.db')
                    cursor = conn.cursor()
                    cutoff_time = time.time() - (${toString cfg.retentionDays} * 24 * 3600)
                    cursor.execute('DELETE FROM node_metrics WHERE timestamp < ?', (cutoff_time,))
                    conn.commit()
                    conn.close()
                    time.sleep(3600)  # Clean up every hour
            
            if __name__ == '__main__':
                init_database()
                
                # Start cleanup thread
                cleanup_thread = threading.Thread(target=cleanup_old_data, daemon=True)
                cleanup_thread.start()
                
                # Start HTTP server
                httpd = HTTPServer(('${cfg.bindAddress}', 8080), DashboardHandler)
                print(f"Dashboard API listening on ${cfg.bindAddress}:8080")
                httpd.serve_forever()
          '';
        in "${pkgs.python3}/bin/python3 ${dashboardScript}";
        
        Restart = "on-failure";
        RestartSec = 10;
        
        # Security settings
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
      };
    };
    
    # Open firewall ports
    networking.firewall = {
      allowedTCPPorts = [ cfg.port 8080 9090 ];
    };
    
    # Install required packages
    environment.systemPackages = with pkgs; [
      python3
      sqlite
      docker-compose
      curl
      jq
    ];
    
    # Backup service
    systemd.services.homelab-dashboard-backup = {
      description = "Backup Home Lab Dashboard data";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        # Create backup directory
        mkdir -p /var/backups/homelab-dashboard
        
        # Backup database and configuration
        ${pkgs.rsync}/bin/rsync -av ${cfg.dataDir}/ /var/backups/homelab-dashboard/
        
        # Remove old backups (keep 7 days)
        find /var/backups/homelab-dashboard -name "*.tar.gz" -mtime +7 -delete
        
        # Create compressed backup
        cd /var/backups
        ${pkgs.gnutar}/bin/tar -czf homelab-dashboard/backup-$(date +%Y%m%d-%H%M%S).tar.gz homelab-dashboard/
      '';
    };
    
    systemd.timers.homelab-dashboard-backup = {
      description = "Backup Home Lab Dashboard daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}