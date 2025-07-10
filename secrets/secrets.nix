# Secrets Configuration Template
# This file shows how to configure secrets for the home lab infrastructure

let
  # Add your age public key here
  # Generate with: age-keygen -o ~/.age/key.txt
  adminKey = "age1..."; # Replace with your actual age public key
in
{
  # Tailscale authentication key
  # Generate at: https://login.tailscale.com/admin/settings/keys
  # Command: echo "tskey-auth-..." | age -r $(cat ~/.age/key.txt | grep public | cut -d' ' -f4) > secrets/tailscale-authkey.age
  "tailscale-authkey.age".publicKeys = [ adminKey ];

  # Nginx Proxy Manager admin password
  # Command: echo "secure-password" | age -r $(cat ~/.age/key.txt | grep public | cut -d' ' -f4) > secrets/npm-admin-password.age
  "npm-admin-password.age".publicKeys = [ adminKey ];

  # AdGuard Home admin password
  # Command: echo "secure-password" | age -r $(cat ~/.age/key.txt | grep public | cut -d' ' -f4) > secrets/adguard-admin-password.age
  "adguard-admin-password.age".publicKeys = [ adminKey ];

  # Grafana admin password
  # Command: echo "secure-password" | age -r $(cat ~/.age/key.txt | grep public | cut -d' ' -f4) > secrets/grafana-admin-password.age
  "grafana-admin-password.age".publicKeys = [ adminKey ];

  # SSH host keys (optional, for consistent host identity)
  # Command: ssh-keyscan hostname | age -r $(cat ~/.age/key.txt | grep public | cut -d' ' -f4) > secrets/ssh-host-keys.age
  "ssh-host-keys.age".publicKeys = [ adminKey ];
}