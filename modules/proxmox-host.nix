# Proxmox Host Module
# Configures Proxmox VE using the proxmox-nixos overlay

{ config, lib, pkgs, proxmox-nixos, ... }:

with lib;

let
  cfg = config.services.proxmox-ve;
  
  # Additional custom options for our home lab
  homeLabCfg = config.homelab.proxmox;
in
{
  # Define our own custom options under homelab namespace to avoid conflicts
  options.homelab.proxmox = {
    enableCustomConfig = mkEnableOption "Custom Proxmox configuration for home lab";
    
    enableBackupCleanup = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic backup cleanup";
    };
    
    enablePerformanceTuning = mkOption {
      type = types.bool;
      default = true;
      description = "Enable performance tuning for virtualization";
    };
    
    enableMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable monitoring and metrics";
    };
  };

  config = mkIf cfg.enable {
    # Configure web interface (remove the conflicting enable = true)
    # Note: services.proxmox-ve.enable should be set in host config
    
    # Networking configuration for Proxmox web UI
    networking.firewall.allowedTCPPorts = [ 8006 ];  # Proxmox web UI
    
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
    
    # Required system packages (only include packages that exist in nixpkgs)
    environment.systemPackages = with pkgs; [
      # pve-manager  # This might not exist in nixpkgs
      qemu
      bridge-utils
      # vlan         # This might not exist as a separate package
      # ifenslave    # This might not exist as a separate package  
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
    
    # Configure storage - note: some services may not exist in standard nixpkgs
    services.lvm.enable = true;
    # services.zfs.enable = true;  # ZFS might not be available as a service option
    
    # Enable ZFS support at boot level instead
    boot.supportedFilesystems = [ "zfs" ];
    
    # Enable cluster features if configured (remove problematic corosync config)
    # services.corosync = mkIf cfg.clusterMode {
    #   enable = true;
    #   nodelist = [
    #     {
    #       nodeid = cfg.nodeId;
    #       name = config.networking.hostName;
    #       ring_addrs = [ "127.0.0.1" ];  # Will be overridden by actual cluster config
    #     }
    #   ];
    # };
    
    # Note: Proxmox backup client configuration is done through Proxmox web interface
    # or external configuration management tools
    
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
    
    # Configure backup retention (conditional on custom config)
    systemd.services.proxmox-backup-cleanup = mkIf homeLabCfg.enableBackupCleanup {
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
    
    systemd.timers.proxmox-backup-cleanup = mkIf homeLabCfg.enableBackupCleanup {
      description = "Run Proxmox backup cleanup daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
    
    # Configure CPU governor for performance (conditional)
    powerManagement.cpuFreqGovernor = mkIf homeLabCfg.enablePerformanceTuning "performance";
    
    # Enable hugepages for better VM performance (conditional)
    boot.kernelParams = mkIf homeLabCfg.enablePerformanceTuning [
      "hugepages=1024"
      "default_hugepagesz=2M"
      "hugepagesz=2M"
    ];
  };
}