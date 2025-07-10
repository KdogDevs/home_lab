# ARM Control Node Configuration
# This is the main control node running on Netcup ARM VPS

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # System configuration
  system.stateVersion = "24.05";
  
  # Networking
  networking = {
    hostName = "arm-control";
    
    # Enable firewall with specific rules
    firewall = {
      enable = true;
      allowedTCPPorts = [ 
        22    # SSH
        80    # HTTP (Nginx Proxy Manager)
        443   # HTTPS (Nginx Proxy Manager)
        8006  # Proxmox Web UI
        81    # Nginx Proxy Manager Admin
        3000  # Dashboard
      ];
      allowedUDPPorts = [ 
        41641 # Tailscale DERP relay
      ];
      
      # Trust Tailscale interface
      trustedInterfaces = [ "tailscale0" ];
    };
    
    # Use systemd-networkd for better network management
    useNetworkd = true;
  };
  
  # Enable SSH
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
  
  # Tailscale configuration (exit node + subnet router)
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    authKeyFile = "/run/agenix/tailscale-authkey";
    extraUpFlags = [
      "--exit-node"
      "--advertise-exit-node"
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
    
    # Enable IP forwarding for exit node functionality
    kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
  
  # Services specific to control node
  services.prometheus = {
    enable = true;
    port = 9090;
    
    # Only accessible via Tailscale
    listenAddress = "127.0.0.1";
    
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{
          targets = [ "localhost:9090" ];
        }];
      }
    ];
  };
  
  # Enable container runtime for additional services
  virtualisation.docker.enable = true;
  
  # Automatic system updates
  system.autoUpgrade = {
    enable = true;
    flake = "github:KdogDevs/home_lab#arm-control";
    flags = [
      "--update-input"
      "nixpkgs"
      "--commit-lock-file"
    ];
    dates = "daily";
    randomizedDelaySec = "45min";
  };
}