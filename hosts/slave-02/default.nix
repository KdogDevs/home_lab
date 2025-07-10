# Slave Node 02 Configuration
# Copy of slave-01 with hostname change

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/proxmox-host.nix
  ];

  # System configuration
  system.stateVersion = "24.05";
  
  # Enable Proxmox VE (use only basic options that exist)
  services.proxmox-ve = {
    enable = true;
    ipAddress = "127.0.0.1";  # Default to localhost, will be configured later
  };
  
  # Enable custom home lab Proxmox configuration
  homelab.proxmox = {
    enableCustomConfig = true;
    enableBackupCleanup = true;
    enablePerformanceTuning = true;
    enableMonitoring = true;
  };
  
  # Networking
  networking = {
    hostName = "slave-02";
    hostId = "7f4c9b2a";  # Required for ZFS (8 random hex characters)
    
    # Enable firewall but only allow Tailscale traffic
    firewall = {
      enable = true;
      allowedTCPPorts = [ 
        22    # SSH (only via Tailscale)
        8006  # Proxmox Web UI (only via Tailscale)
      ];
      
      # Trust Tailscale interface
      trustedInterfaces = [ "tailscale0" ];
      
      # Block all other traffic
      allowPing = false;
      logReversePathDrops = true;
    };
    
    # Use systemd-networkd
    useNetworkd = true;
  };
  
  # Enable SSH but only accessible via Tailscale
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
  
  # Users
  users.users.root = {
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      # "ssh-rsa AAAAB3NzaC1yc2E... user@example.com"
    ];
  };
  
  # Create a non-root user for management
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      # "ssh-rsa AAAAB3NzaC1yc2E... user@example.com"
    ];
  };
  
  # Enable sudo for wheel group
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };
  
  # System packages
  environment.systemPackages = with pkgs; [
    git
    htop
    curl
    wget
    vim
    tmux
    jq
  ];
  
  # Enable Nix flakes
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    
    # Automatic garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
  
  # Tailscale configuration (no exit node, auto-auth)  
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    # authKeyFile = "/run/agenix/tailscale-authkey";  # Commented until agenix secrets are set up
    extraUpFlags = [
      "--ssh"
    ];
  };
  
  # Time zone
  time.timeZone = "UTC";
  
  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  
  # Boot configuration
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };
  
  # Enable container runtime for VMs and containers
  virtualisation.docker.enable = true;
  
  # Automatic system updates
  system.autoUpgrade = {
    enable = true;
    flake = "github:KdogDevs/home_lab#slave-02";
    flags = [
      "--update-input"
      "nixpkgs"
      "--commit-lock-file"
    ];
    dates = "daily";
    randomizedDelaySec = "45min";
  };
  
  # Enable monitoring
  services.prometheus.exporters = {
    node = {
      enable = true;
      enabledCollectors = [
        "systemd"
        "processes"
        "network"
        "diskstats"
        "filesystem"
        "loadavg"
        "meminfo"
        "netdev"
        "stat"
        "time"
        "uname"
      ];
      # Only accessible via Tailscale
      listenAddress = "127.0.0.1";
    };
  };
}