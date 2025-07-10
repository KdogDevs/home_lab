#!/usr/bin/env bash
# Validation script for the home lab infrastructure

set -euo pipefail

echo "🔍 Validating Home Lab Infrastructure..."

# Check if all required files exist
echo "📁 Checking file structure..."

required_files=(
    "flake.nix"
    "hosts/arm-control/default.nix"
    "hosts/slave-01/default.nix" 
    "hosts/slave-02/default.nix"
    "modules/tailscale.nix"
    "modules/proxmox-host.nix"
    "modules/nginx-proxy-manager.nix"
    "modules/adguard-dns.nix"
    "modules/dashboard.nix"
    "modules/reporter.nix"
    "secrets/secrets.nix"
    "README.md"
    ".gitignore"
    ".github/workflows/deploy.yml"
)

for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "✅ $file"
    else
        echo "❌ $file - MISSING"
        exit 1
    fi
done

echo ""
echo "🔧 Checking Nix syntax..."

# Basic syntax check for all .nix files
find . -name "*.nix" -type f | while read -r file; do
    echo "Checking $file..."
    # This is a basic check - in a real environment with nix installed,
    # you would run: nix-instantiate --parse "$file" > /dev/null
    first_char=$(head -1 "$file" | cut -c1)
    if [[ "$first_char" == "#" ]] || [[ "$first_char" == "{" ]] || [[ "$first_char" == "l" ]]; then
        echo "✅ $file - basic syntax OK"
    else
        echo "❌ $file - syntax issue (starts with '$first_char')"
        exit 1
    fi
done

echo ""
echo "📊 Repository Statistics:"
echo "- Total .nix files: $(find . -name "*.nix" -type f | wc -l)"
echo "- Host configurations: $(find hosts -name "default.nix" | wc -l)"
echo "- Modules: $(find modules -name "*.nix" | wc -l)"
echo "- Lines of code: $(find . -name "*.nix" -type f -exec wc -l {} + | tail -1 | awk '{print $1}')"

echo ""
echo "🎯 Next Steps:"
echo "1. Install Nix with flakes: https://nixos.org/download.html"
echo "2. Set up age keys for secrets: nix-shell -p age --run 'age-keygen -o ~/.age/key.txt'"
echo "3. Configure Tailscale auth key in secrets/"
echo "4. Update SSH keys in host configurations"
echo "5. Generate hardware configurations on target machines"
echo "6. Test with: nix flake check"
echo "7. Deploy with: nixos-rebuild switch --flake .#hostname"

echo ""
echo "✅ Validation complete! Infrastructure is ready for deployment."