{
  description = "Home Lab Infrastructure with Proxmox, Tailscale, and Centralized Management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Proxmox overlay for NixOS
    proxmox-nixos = {
      url = "github:SaumonNet/proxmox-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # For managing secrets
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, proxmox-nixos, agenix, ... }:
    let
      system = "x86_64-linux";
      
      # Apply overlays to make proxmox packages available
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ proxmox-nixos.overlays.${system} ];
      };
      
      # Common configuration shared across all hosts
      commonModules = [
        agenix.nixosModules.default
        # ./modules/tailscale.nix  # Remove custom tailscale module, use built-in
      ];
      
      # Helper function to create a host configuration
      mkHost = { hostname, system ? "x86_64-linux", modules ? [] }: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./hosts/${hostname}
          proxmox-nixos.nixosModules.proxmox-ve
          # Apply the overlay to this system correctly
          { nixpkgs.overlays = [ proxmox-nixos.overlays.${system} ]; }
        ] ++ commonModules ++ modules;
        specialArgs = {
          inherit self;
          proxmox-nixos = proxmox-nixos;
        };
      };
      
    in {
      # NixOS configurations for each host
      nixosConfigurations = {
        # ARM control node (Netcup VPS)
        arm-control = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            ./hosts/arm-control
            proxmox-nixos.nixosModules.proxmox-ve
            # Apply the overlay for aarch64 system
            { nixpkgs.overlays = [ proxmox-nixos.overlays."aarch64-linux" ]; }
            ./modules/nginx-proxy-manager.nix
            ./modules/adguard-dns.nix
            ./modules/dashboard.nix
          ] ++ commonModules;
          specialArgs = {
            inherit self;
            proxmox-nixos = proxmox-nixos;
          };
        };
        
        # x86 slave nodes
        slave-01 = mkHost {
          hostname = "slave-01";
          modules = [
            ./modules/reporter.nix
          ];
        };
        
        slave-02 = mkHost {
          hostname = "slave-02";
          modules = [
            ./modules/reporter.nix
          ];
        };
      };
      
      # Development shell for managing the infrastructure
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixos-rebuild
          git
          age
          ssh-to-age
          agenix.packages.${system}.default
        ];
        
        shellHook = ''
          echo "Home Lab Infrastructure Development Shell"
          echo "Available commands:"
          echo "  nix flake check                    - Check flake configuration"
          echo "  nixos-rebuild switch --flake .#<host> - Deploy to specific host"
          echo "  agenix -e <secret>                 - Edit encrypted secrets"
        '';
      };
      
      # Installer script for new slaves
      packages.${system}.installer = pkgs.writeShellScriptBin "installer" ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        if [ $# -ne 1 ]; then
          echo "Usage: $0 <hostname>"
          echo "Available hosts: slave-01, slave-02, ..."
          exit 1
        fi
        
        HOSTNAME="$1"
        
        echo "Installing NixOS for host: $HOSTNAME"
        echo "This will:"
        echo "1. Partition the disk"
        echo "2. Install NixOS with the $HOSTNAME configuration"
        echo "3. Configure Tailscale and Proxmox"
        
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo "Installation cancelled."
          exit 1
        fi
        
        # Basic disk partitioning (adjust as needed)
        echo "Partitioning disk..."
        parted /dev/sda -- mklabel gpt
        parted /dev/sda -- mkpart primary 512MB 100%
        parted /dev/sda -- mkpart ESP fat32 1MB 512MB
        parted /dev/sda -- set 2 esp on
        
        # Format partitions
        mkfs.ext4 -L nixos /dev/sda1
        mkfs.fat -F 32 -n boot /dev/sda2
        
        # Mount partitions
        mount /dev/disk/by-label/nixos /mnt
        mkdir -p /mnt/boot
        mount /dev/disk/by-label/boot /mnt/boot
        
        # Generate hardware config
        nixos-generate-config --root /mnt
        
        # Install NixOS with our configuration
        nixos-install --flake "github:KdogDevs/home_lab#$HOSTNAME"
        
        echo "Installation complete! Reboot and the system will join the Tailscale network automatically."
      '';
      
      # Formatter for the flake
      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}