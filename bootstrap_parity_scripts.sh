#!/usr/bin/env bash
# Bootstrap script for cross-language-crystal-parity
# This script helps bootstrap the parity scripts without hardcoded paths

set -euo pipefail

echo "Bootstrapping cross-language-crystal-parity scripts..."

# Try to find the skill directory
SKILL_DIR=""

# Common locations to check
LOCATIONS=(
  "$HOME/.agents/skills/crystal_forge/skills/cross-language-crystal-parity"
  "$HOME/.config/opencode/skills/cross-language-crystal-parity"
  "$HOME/.agents/skills/cross-language-crystal-parity"
  "/usr/local/share/agents/skills/cross-language-crystal-parity"
)

for loc in "${LOCATIONS[@]}"; do
  if [[ -d "$loc" ]]; then
    SKILL_DIR="$loc"
    echo "Found skill at: $SKILL_DIR"
    break
  fi
done

# If not found, try to search
if [[ -z "$SKILL_DIR" ]]; then
  echo "Searching for skill directory..."
  found=$(find "$HOME/.agents" "$HOME/.config/opencode" -name "cross-language-crystal-parity" -type d 2>/dev/null | head -1)
  if [[ -n "$found" ]]; then
    SKILL_DIR="$found"
    echo "Found skill at: $SKILL_DIR"
  fi
fi

if [[ -z "$SKILL_DIR" ]]; then
  echo "Error: Could not find cross-language-crystal-parity skill directory."
  echo "Please check your skill installation."
  echo "Common locations:"
  for loc in "${LOCATIONS[@]}"; do
    echo "  - $loc"
  done
  exit 1
fi

# Create scripts directory
mkdir -p ./scripts

# Copy scripts
echo "Copying scripts from $SKILL_DIR/scripts/ to ./scripts/"
cp "$SKILL_DIR"/scripts/* ./scripts/

# Make executable
chmod +x ./scripts/*.sh ./scripts/*.rb

echo "Done! Parity scripts bootstrapped to ./scripts/"
echo ""
echo "Next steps:"
echo "1. Run: ./scripts/ensure_parity_plan.sh . vendor/your-upstream-repo rust auto 0"
echo "2. Check project's AGENTS.md for quality gates and conventions"
echo "3. Update plans/inventory/rust_port_inventory.tsv as you work"