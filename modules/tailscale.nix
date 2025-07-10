# Tailscale Module
# Always-on, auto-auth, exit-node-optional configuration

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.tailscale;
in
{
  options.services.tailscale = {
    enable = mkEnableOption "Tailscale VPN service";
    
    authKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to file containing Tailscale authentication key";
    };
    
    useRoutingFeatures = mkOption {
      type = types.enum [ "none" "client" "server" "both" ];
      default = "client";
      description = "Enable IP forwarding and/or subnet routing";
    };
    
    extraUpFlags = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra flags to pass to tailscale up";
    };
    
    exitNode = mkOption {
      type = types.bool;
      default = false;
      description = "Enable as exit node";
    };
    
    advertiseRoutes = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Subnet routes to advertise";
    };
  };

  config = mkIf cfg.enable {
    # Install Tailscale and custom scripts
    environment.systemPackages = with pkgs; [ 
      tailscale 
      (writeScriptBin "tailscale-reconnect" ''
        #!/usr/bin/env bash
        echo "Reconnecting to Tailscale..."
        sudo systemctl restart tailscale-autoconnect
        echo "Reconnection complete. Status:"
        tailscale status
      '')
    ];
    
    # Enable the Tailscale service
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = cfg.useRoutingFeatures;
    };
    
    # Configure networking
    networking.firewall = {
      # Allow the Tailscale UDP port
      allowedUDPPorts = [ 41641 ];
      
      # Trust the Tailscale interface
      trustedInterfaces = [ "tailscale0" ];
      
      # Allow forwarding for exit node functionality
      checkReversePath = "loose";
    };
    
    # Enable IP forwarding if needed
    boot.kernel.sysctl = mkIf (cfg.exitNode || cfg.advertiseRoutes != []) {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
    
    # Systemd service for authentication
    systemd.services.tailscale-autoconnect = {
      description = "Automatic connection to Tailscale";
      after = [ "network-pre.target" "tailscale.service" ];
      wants = [ "network-pre.target" "tailscale.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = let
        upFlags = concatStringsSep " " (
          cfg.extraUpFlags
          ++ optional cfg.exitNode "--advertise-exit-node"
          ++ optional (cfg.advertiseRoutes != []) "--advertise-routes=${concatStringsSep "," cfg.advertiseRoutes}"
          ++ optional (cfg.authKeyFile != null) "--auth-key=file:${cfg.authKeyFile}"
        );
      in ''
        # Wait for tailscale to be ready
        sleep 2
        
        # Check if already connected
        status="$(${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -r '.BackendState')"
        if [ "$status" = "Running" ]; then
          echo "Already connected to Tailscale"
          exit 0
        fi
        
        # Connect to Tailscale
        ${pkgs.tailscale}/bin/tailscale up ${upFlags}
      '';
    };
    
    # Ensure Tailscale starts early
    systemd.services.tailscale.wantedBy = [ "multi-user.target" ];
  };
}