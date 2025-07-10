# Reporter Module
# Lightweight agent shipped to every non-control host

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.homelab-reporter;
in
{
  options.services.homelab-reporter = {
    enable = mkEnableOption "Home Lab Reporter Agent";
    
    controllerUrl = mkOption {
      type = types.str;
      default = "http://100.64.0.1:8080";  # Tailscale IP of control node
      description = "URL of the dashboard API endpoint";
    };
    
    reportInterval = mkOption {
      type = types.int;
      default = 300;
      description = "Interval in seconds to report metrics";
    };
    
    hostname = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Hostname to report as";
    };
    
    enableSystemMetrics = mkOption {
      type = types.bool;
      default = true;
      description = "Enable system metrics collection";
    };
    
    enableProxmoxMetrics = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Proxmox metrics collection";
    };
    
    enableDockerMetrics = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Docker metrics collection";
    };
    
    customMetrics = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Custom metrics to collect (command to run)";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.homelab-reporter = {
      group = "homelab-reporter";
      isSystemUser = true;
      extraGroups = [ "docker" ];  # For Docker metrics
    };
    
    users.groups.homelab-reporter = {};
    
    # Reporter script
    systemd.services.homelab-reporter = {
      description = "Home Lab Reporter Agent";
      after = [ "network.target" "tailscale.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "simple";
        User = "homelab-reporter";
        Group = "homelab-reporter";
        Restart = "on-failure";
        RestartSec = 30;
        
        ExecStart = let
          reporterScript = pkgs.writeScript "homelab-reporter.py" ''
            #!/usr/bin/env python3
            import json
            import time
            import subprocess
            import psutil
            import requests
            import os
            import socket
            from datetime import datetime
            
            class HomelabReporter:
                def __init__(self):
                    self.controller_url = "${cfg.controllerUrl}"
                    self.hostname = "${cfg.hostname}"
                    self.report_interval = ${toString cfg.reportInterval}
                    self.enable_system = ${if cfg.enableSystemMetrics then "True" else "False"}
                    self.enable_proxmox = ${if cfg.enableProxmoxMetrics then "True" else "False"}
                    self.enable_docker = ${if cfg.enableDockerMetrics then "True" else "False"}
                    self.custom_metrics = ${builtins.toJSON cfg.customMetrics}
                
                def collect_system_metrics(self):
                    if not self.enable_system:
                        return {}
                    
                    try:
                        # CPU usage
                        cpu_percent = psutil.cpu_percent(interval=1)
                        cpu_count = psutil.cpu_count()
                        
                        # Memory usage
                        memory = psutil.virtual_memory()
                        
                        # Disk usage
                        disk_usage = psutil.disk_usage('/')
                        
                        # Network statistics
                        net_io = psutil.net_io_counters()
                        
                        # Load average
                        load_avg = os.getloadavg()
                        
                        # Boot time
                        boot_time = psutil.boot_time()
                        
                        return {
                            'cpu': {
                                'percent': cpu_percent,
                                'count': cpu_count,
                                'load_avg': {
                                    '1min': load_avg[0],
                                    '5min': load_avg[1],
                                    '15min': load_avg[2]
                                }
                            },
                            'memory': {
                                'total': memory.total,
                                'available': memory.available,
                                'percent': memory.percent,
                                'used': memory.used,
                                'free': memory.free
                            },
                            'disk': {
                                'total': disk_usage.total,
                                'used': disk_usage.used,
                                'free': disk_usage.free,
                                'percent': (disk_usage.used / disk_usage.total) * 100
                            },
                            'network': {
                                'bytes_sent': net_io.bytes_sent,
                                'bytes_recv': net_io.bytes_recv,
                                'packets_sent': net_io.packets_sent,
                                'packets_recv': net_io.packets_recv
                            },
                            'uptime': time.time() - boot_time
                        }
                    except Exception as e:
                        print(f"Error collecting system metrics: {e}")
                        return {}
                
                def collect_proxmox_metrics(self):
                    if not self.enable_proxmox:
                        return {}
                    
                    try:
                        # Check if Proxmox is running
                        result = subprocess.run(['systemctl', 'is-active', 'pve-cluster'], 
                                              capture_output=True, text=True)
                        pve_running = result.returncode == 0
                        
                        metrics = {'pve_running': pve_running}
                        
                        if pve_running:
                            # Get cluster status
                            try:
                                result = subprocess.run(['pvecm', 'status'], 
                                                      capture_output=True, text=True)
                                if result.returncode == 0:
                                    metrics['cluster_status'] = result.stdout.strip()
                            except:
                                pass
                            
                            # Get node status
                            try:
                                result = subprocess.run(['pvecm', 'nodes'], 
                                                      capture_output=True, text=True)
                                if result.returncode == 0:
                                    metrics['nodes'] = result.stdout.strip()
                            except:
                                pass
                        
                        return metrics
                    except Exception as e:
                        print(f"Error collecting Proxmox metrics: {e}")
                        return {}
                
                def collect_docker_metrics(self):
                    if not self.enable_docker:
                        return {}
                    
                    try:
                        # Get Docker info
                        result = subprocess.run(['docker', 'info', '--format', '{{json .}}'], 
                                              capture_output=True, text=True)
                        if result.returncode == 0:
                            docker_info = json.loads(result.stdout)
                            
                            # Get container stats
                            result = subprocess.run(['docker', 'ps', '--format', '{{json .}}'], 
                                                  capture_output=True, text=True)
                            containers = []
                            if result.returncode == 0:
                                for line in result.stdout.strip().split('\n'):
                                    if line:
                                        containers.append(json.loads(line))
                            
                            return {
                                'info': {
                                    'containers': docker_info.get('Containers', 0),
                                    'images': docker_info.get('Images', 0),
                                    'server_version': docker_info.get('ServerVersion', 'unknown')
                                },
                                'containers': containers
                            }
                    except Exception as e:
                        print(f"Error collecting Docker metrics: {e}")
                        return {}
                
                def collect_custom_metrics(self):
                    metrics = {}
                    
                    for name, command in self.custom_metrics.items():
                        try:
                            result = subprocess.run(command, shell=True, 
                                                  capture_output=True, text=True, timeout=30)
                            if result.returncode == 0:
                                try:
                                    # Try to parse as JSON
                                    metrics[name] = json.loads(result.stdout)
                                except json.JSONDecodeError:
                                    # Fall back to string
                                    metrics[name] = result.stdout.strip()
                        except Exception as e:
                            print(f"Error collecting custom metric {name}: {e}")
                            metrics[name] = {"error": str(e)}
                    
                    return metrics
                
                def collect_all_metrics(self):
                    metrics = {
                        'timestamp': time.time(),
                        'hostname': self.hostname,
                        'system': self.collect_system_metrics(),
                        'proxmox': self.collect_proxmox_metrics(),
                        'docker': self.collect_docker_metrics(),
                        'custom': self.collect_custom_metrics()
                    }
                    
                    return metrics
                
                def send_metrics(self, metrics):
                    try:
                        payload = {
                            'hostname': self.hostname,
                            'metrics': metrics
                        }
                        
                        response = requests.post(
                            f"{self.controller_url}/api/metrics",
                            json=payload,
                            timeout=30,
                            headers={'Content-Type': 'application/json'}
                        )
                        
                        if response.status_code == 200:
                            print(f"Metrics sent successfully at {datetime.now()}")
                        else:
                            print(f"Failed to send metrics: {response.status_code} - {response.text}")
                    
                    except Exception as e:
                        print(f"Error sending metrics: {e}")
                
                def run(self):
                    print(f"Starting Home Lab Reporter for {self.hostname}")
                    print(f"Controller URL: {self.controller_url}")
                    print(f"Report interval: {self.report_interval} seconds")
                    
                    while True:
                        try:
                            metrics = self.collect_all_metrics()
                            self.send_metrics(metrics)
                        except Exception as e:
                            print(f"Error in main loop: {e}")
                        
                        time.sleep(self.report_interval)
            
            if __name__ == '__main__':
                reporter = HomelabReporter()
                reporter.run()
          '';
        in "${pkgs.python3}/bin/python3 ${reporterScript}";
        
        # Security settings
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = [ "/var/lib/docker" ];
      };
    };
    
    # Install required packages
    environment.systemPackages = with pkgs; [
      python3
      python3Packages.psutil
      python3Packages.requests
      curl
      jq
    ];
    
    # Health check service
    systemd.services.homelab-reporter-health = {
      description = "Health check for Home Lab Reporter";
      serviceConfig = {
        Type = "oneshot";
        User = "homelab-reporter";
        Group = "homelab-reporter";
      };
      script = ''
        # Check if the reporter service is running
        if ! systemctl is-active homelab-reporter >/dev/null 2>&1; then
          echo "Reporter service is not running"
          exit 1
        fi
        
        # Check if we can reach the controller
        if ! ${pkgs.curl}/bin/curl -f -s --max-time 10 "${cfg.controllerUrl}/health" >/dev/null; then
          echo "Cannot reach controller at ${cfg.controllerUrl}"
          exit 1
        fi
        
        echo "Reporter health check passed"
      '';
    };
    
    systemd.timers.homelab-reporter-health = {
      description = "Health check for Home Lab Reporter every 10 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/10";
        Persistent = true;
      };
    };
  };
}