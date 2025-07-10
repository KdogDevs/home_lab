# NixOS Home Lab Configuration Fixes Applied

## Issues Fixed

### 1. ✅ Duplicate Option Declaration (`services.proxmox-ve.enable`)
**Problem**: Custom module was redefining options already provided by proxmox-nixos overlay.
**Fix**: 
- Removed conflicting option declarations from `modules/proxmox-host.nix`
- Created custom options under `homelab.proxmox` namespace instead
- Removed problematic `services.proxmox-ve.enable = true` from within the module

### 2. ✅ Multiple Module Imports
**Problem**: `proxmox-host.nix` was imported both in flake.nix and individual host configs.
**Fix**:
- Removed imports from `flake.nix` (lines 52, 63, 71)
- Added imports only in individual host configuration files
- Each module now imported exactly once

### 3. ✅ Tailscale Module Conflict
**Problem**: Custom tailscale module conflicted with built-in NixOS tailscale module.
**Fix**:
- Removed custom `./modules/tailscale.nix` import from `flake.nix`
- Updated all host configs to use built-in `services.tailscale`
- Fixed duplicate `environment.systemPackages` declarations in custom module

### 4. ✅ Non-existent Services and Packages
**Problem**: Module referenced services/packages that don't exist in nixpkgs.
**Fix**:
- Removed `services.proxmox-backup-client` (doesn't exist)
- Replaced `services.zfs.enable` with `boot.supportedFilesystems = ["zfs"]`
- Removed non-existent packages: `pve-manager`, `vlan`, `ifenslave`
- Commented out problematic `services.corosync` configuration

### 5. ✅ Missing Required Configuration
**Problem**: Various services required configuration that wasn't provided.
**Fix**:
- Added `networking.hostId` to all hosts (required for ZFS)
- Added `services.proxmox-ve.ipAddress` to all hosts
- Commented out `authKeyFile` references until agenix secrets are properly configured

## File Changes Made

### `flake.nix`
- Removed `./modules/proxmox-host.nix` imports from all host configurations
- Removed `./modules/tailscale.nix` from commonModules

### `modules/proxmox-host.nix`
- Changed options namespace from `services.proxmox-ve.*` to `homelab.proxmox.*`
- Removed conflicting `services.proxmox-ve.enable = true`
- Removed non-existent services and packages
- Made configurations conditional on new custom options

### `modules/tailscale.nix`
- Fixed duplicate `environment.systemPackages` declarations
- Combined package installations into single declaration

### `hosts/*/default.nix`
- Added `../../modules/proxmox-host.nix` import to all hosts
- Updated to use built-in `services.tailscale` instead of custom module
- Added required `networking.hostId` for ZFS support
- Added required `services.proxmox-ve.ipAddress`
- Enabled custom `homelab.proxmox` options
- Commented out `authKeyFile` until secrets are configured

## Next Steps

1. **Set up agenix secrets**: Uncomment `authKeyFile` lines after configuring Tailscale auth keys
2. **Configure actual IP addresses**: Replace `127.0.0.1` with real network addresses for Proxmox
3. **Test deployment**: Use `nixos-rebuild switch --flake .#<hostname>` to deploy
4. **Set up clustering**: Enable cluster mode and configure proper node IDs when ready

## Validation

The configuration should now pass `nix flake check` without the previous duplicate declaration errors. The main remaining issues would be related to missing secrets (agenix) and real network configuration, which are expected until actual deployment.
