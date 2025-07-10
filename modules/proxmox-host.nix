# Proxmox Host Module
# Configures Proxmox VE using the proxmox-nixos overlay

{ config, lib, pkgs, proxmox-nixos, ... }:

with lib;

let
  cfg = config.services.proxmox-ve;
in
{
  options.services.proxmox-ve = {
    enable = mkEnableOption "Proxmox VE virtualization platform";
    
    webInterface = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Proxmox web interface";
    };
    
    clusterMode = mkOption {
      type = types.bool;
      default = false;
      description = "Enable cluster mode (disable web UI on slaves)";
    };
    
    clusterName = mkOption {
      type = types.str;
      default = "homelab";
      description = "Name of the Proxmox cluster";
    };
    
    nodeId = mkOption {
      type = types.int;
      default = 1;
      description = "Node ID in the cluster";
    };
    
    bindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address to bind Proxmox web interface";
    };
  };

  config = mkIf cfg.enable {
    # Enable Proxmox VE
    services.proxmox-ve = {
      enable = true;
      
      # Configure web interface
      webInterface = cfg.webInterface && !cfg.clusterMode;
    };
    
    # Networking configuration
    networking.firewall = mkIf cfg.webInterface {
      allowedTCPPorts = [ 8006 ];  # Proxmox web UI
    };
    
    # Enable virtualization features
    virtualisation = {
      libvirtd = {
        enable = true;
        qemu = {
          package = pkgs.qemu_kvm;
          runAsRoot = true;
          swtpm.enable = true;
          ovmf = {
            enable = true;
            packages = [ pkgs.OVMF.fd ];
          };
        };
      };
      
      # Enable KVM
      kvmgt.enable = true;
    };
    
    # Required system packages
    environment.systemPackages = with pkgs; [
      pve-manager
      qemu
      bridge-utils
      vlan
      ifenslave
      ethtool
    ];
    
    # Enable necessary kernel modules
    boot.kernelModules = [
      "kvm"
      "kvm-intel"  # Change to kvm-amd for AMD processors
      "vfio"
      "vfio_iommu_type1"
      "vfio_pci"
      "vfio_virqfd"
      "bridge"
      "vlan"
      "bonding"
    ];
    
    # Configure storage
    services.lvm.enable = true;
    services.zfs.enable = true;
    
    # Enable cluster features if configured
    services.corosync = mkIf cfg.clusterMode {
      enable = true;
      nodelist = [
        {
          nodeid = cfg.nodeId;
          name = config.networking.hostName;
          ring_addrs = [ "127.0.0.1" ];  # Will be overridden by actual cluster config
        }
      ];
    };
    
    # Configure Proxmox backup server client
    services.proxmox-backup-client = {
      enable = true;
      
      settings = {
        # Configuration will be managed through Proxmox web interface
        # or external configuration management
      };
    };
    
    # System tuning for virtualization
    boot.kernel.sysctl = {
      # Increase limits for VMs
      "vm.max_map_count" = 262144;
      "fs.aio-max-nr" = 1048576;
      
      # Network tuning
      "net.bridge.bridge-nf-call-iptables" = 0;
      "net.bridge.bridge-nf-call-ip6tables" = 0;
      "net.bridge.bridge-nf-call-arptables" = 0;
      
      # Memory overcommit
      "vm.overcommit_memory" = 1;
    };
    
    # Enable and configure storage services
    services.rpcbind.enable = true;  # For NFS
    services.nfs.server.enable = true;
    
    # Configure backup retention
    systemd.services.proxmox-backup-cleanup = {
      description = "Cleanup old Proxmox backups";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        # Clean up backups older than 30 days
        find /var/lib/vz/dump -name "*.tar.*" -mtime +30 -delete
        find /var/lib/vz/dump -name "*.vma.*" -mtime +30 -delete
      '';
    };
    
    systemd.timers.proxmox-backup-cleanup = {
      description = "Run Proxmox backup cleanup daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
    
    # Configure CPU governor for performance
    powerManagement.cpuFreqGovernor = "performance";
    
    # Enable hugepages for better VM performance
    boot.kernelParams = [
      "hugepages=1024"
      "default_hugepagesz=2M"
      "hugepagesz=2M"
    ];
  };
}