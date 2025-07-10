# Home Lab Infrastructure

A NixOS-based home lab infrastructure with Proxmox, Tailscale, and centralized management.

## Overview

This repository contains a declarative, reproducible infrastructure for a home lab setup that includes:

- **Control Node**: ARM-based VPS (Netcup) serving as the central management hub
- **Slave Nodes**: Multiple x86/ARM boxes managed through Proxmox
- **Networking**: Tailscale for secure connectivity between nodes
- **Monitoring**: Centralized dashboard with Grafana and Prometheus
- **Reverse Proxy**: Nginx Proxy Manager for public service exposure
- **DNS**: AdGuard Home for network-wide ad blocking

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Internet                                 │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          │ 80/443
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                 ARM Control Node                               │
│                 (Netcup VPS)                                   │
├─────────────────────────────────────────────────────────────────┤
│ • Tailscale (exit node)                                       │
│ • Proxmox Web UI                                              │
│ • Nginx Proxy Manager                                         │
│ • AdGuard Home DNS                                             │
│ • Grafana Dashboard                                            │
│ • Prometheus Metrics                                           │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          │ Tailscale Network
                          │
      ┌───────────────────┼───────────────────┐
      │                   │                   │
┌─────▼─────┐       ┌─────▼─────┐       ┌─────▼─────┐
│ Slave-01  │       │ Slave-02  │       │ Slave-XX  │
│ (x86/ARM) │       │ (x86/ARM) │       │ (x86/ARM) │
├───────────┤       ├───────────┤       ├───────────┤
│ • Proxmox │       │ • Proxmox │       │ • Proxmox │
│ • Reporter│       │ • Reporter│       │ • Reporter│
│ • Docker  │       │ • Docker  │       │ • Docker  │
└───────────┘       └───────────┘       └───────────┘
```

## Quick Start

### Prerequisites

1. **Nix with flakes enabled**: Install Nix and enable flakes
2. **SSH access**: Configure SSH keys for all nodes
3. **Tailscale account**: Set up a Tailscale account and obtain auth keys

### Initial Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/KdogDevs/home_lab.git
   cd home_lab
   ```

2. **Configure secrets**:
   ```bash
   # Generate age keys
   nix-shell -p age --run "age-keygen -o ~/.age/key.txt"
   
   # Create secrets directory
   mkdir -p secrets
   
   # Add your Tailscale auth key
   echo "your-tailscale-auth-key" | age -r $(cat ~/.age/key.txt | grep public | cut -d' ' -f4) > secrets/tailscale-authkey.age
   ```

3. **Update hardware configurations**:
   - Replace the template UUIDs in `hosts/*/hardware-configuration.nix` with actual values
   - Generate hardware configurations on each target machine:
     ```bash
     nixos-generate-config --dir /tmp/config
     cp /tmp/config/hardware-configuration.nix hosts/your-host/
     ```

4. **Update SSH keys**:
   - Add your SSH public keys to each host configuration in `hosts/*/default.nix`

### Deployment

#### Deploy to Control Node

```bash
# Check configuration
nix flake check

# Deploy to control node
nixos-rebuild switch --flake .#arm-control --target-host root@your-control-node.com
```

#### Deploy to Slave Nodes

```bash
# Deploy to specific slave
nixos-rebuild switch --flake .#slave-01 --target-host root@slave-01-ip

# Or use the installer for new machines
nix run .#installer -- slave-01
```

## Repository Structure

```
.
├── flake.nix                 # Main flake configuration
├── hosts/                    # Host-specific configurations
│   ├── arm-control/         # Control node configuration
│   ├── slave-01/            # First slave node
│   ├── slave-02/            # Second slave node
│   └── ...                  # Additional slaves
├── modules/                  # Reusable NixOS modules
│   ├── tailscale.nix        # Tailscale VPN configuration
│   ├── proxmox-host.nix     # Proxmox virtualization
│   ├── nginx-proxy-manager.nix  # Reverse proxy
│   ├── adguard-dns.nix      # DNS server
│   ├── dashboard.nix        # Monitoring dashboard
│   └── reporter.nix         # Metrics collection agent
├── secrets/                 # Encrypted secrets (age/sops)
├── .gitignore              # Git ignore rules
└── README.md               # This file
```

## Services

### Control Node Services

| Service | Port | Description |
|---------|------|-------------|
| SSH | 22 | System administration |
| HTTP | 80 | Nginx Proxy Manager (public) |
| HTTPS | 443 | Nginx Proxy Manager (public) |
| NPM Admin | 81 | Nginx Proxy Manager admin |
| Grafana | 3000 | Monitoring dashboard |
| Proxmox | 8006 | Proxmox web interface |
| Prometheus | 9090 | Metrics collection |
| Tailscale | 41641/UDP | VPN coordination |

### Slave Node Services

| Service | Port | Description |
|---------|------|-------------|
| SSH | 22 | System administration (Tailscale only) |
| Proxmox | 8006 | Proxmox web interface (Tailscale only) |
| Node Exporter | 9100 | Prometheus metrics |
| Reporter API | 8080 | Custom metrics reporting |

## Configuration

### Adding a New Slave Node

1. **Create host configuration**:
   ```bash
   mkdir -p hosts/slave-03
   cp hosts/slave-01/default.nix hosts/slave-03/
   # Edit hostname and any specific settings
   ```

2. **Add to flake.nix**:
   ```nix
   slave-03 = mkHost {
     hostname = "slave-03";
     modules = [
       ./modules/proxmox-host.nix
       ./modules/reporter.nix
     ];
   };
   ```

3. **Deploy**:
   ```bash
   nix run .#installer -- slave-03
   ```

### Updating Services

Services are configured through the module system. To modify a service:

1. Edit the appropriate module in `modules/`
2. Test with `nix flake check`
3. Deploy with `nixos-rebuild switch --flake .#hostname`

### Managing Secrets

This setup uses age for secret management:

```bash
# Encrypt a new secret
echo "secret-value" | age -r $(cat ~/.age/key.txt | grep public | cut -d' ' -f4) > secrets/secret-name.age

# Edit an existing secret
age -d -i ~/.age/key.txt secrets/secret-name.age | $EDITOR /dev/stdin | age -r $(cat ~/.age/key.txt | grep public | cut -d' ' -f4) > secrets/secret-name.age
```

## Monitoring

The dashboard provides:

- **System Metrics**: CPU, memory, disk, network usage
- **Proxmox Status**: VM/container status, cluster health
- **Docker Metrics**: Container status and resource usage
- **Custom Metrics**: User-defined monitoring points

Access the dashboard at: `http://your-control-node:3000`

## Networking

### Tailscale Configuration

- **Control Node**: Exit node enabled, advertises local subnets
- **Slave Nodes**: Auto-connect via auth key, no exit node capability
- **DNS**: AdGuard Home available to all Tailscale clients

### Firewall Rules

- **Control Node**: Public ports 80, 443, 22; Tailscale interface trusted
- **Slave Nodes**: No public ports; only Tailscale and established connections

## Backup Strategy

Each service includes automated backups:

- **Daily backups** of configuration and data
- **7-day retention** for most services
- **30-day retention** for monitoring data
- **Compressed archives** stored in `/var/backups/`

## Troubleshooting

### Common Issues

1. **Tailscale connection fails**:
   ```bash
   sudo systemctl restart tailscale-autoconnect
   tailscale status
   ```

2. **Service won't start**:
   ```bash
   sudo systemctl status service-name
   sudo journalctl -u service-name -f
   ```

3. **Flake evaluation errors**:
   ```bash
   nix flake check --show-trace
   ```

### Logs

Service logs are available via journalctl:
```bash
sudo journalctl -u service-name -f
```

## Development

### Local Development

```bash
# Enter development shell
nix develop

# Available commands will be shown
```

### Testing Changes

```bash
# Check syntax and dependencies
nix flake check

# Build without deploying
nix build .#nixosConfigurations.hostname.config.system.build.toplevel

# Test in VM
nixos-rebuild build-vm --flake .#hostname
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `nix flake check`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [NixOS](https://nixos.org/) for the declarative system configuration
- [Proxmox](https://proxmox.com/) for virtualization capabilities
- [Tailscale](https://tailscale.com/) for secure networking
- [SaumonNet/proxmox-nixos](https://github.com/SaumonNet/proxmox-nixos) for the Proxmox overlay