#!/usr/bin/env bash
set -euo pipefail

# Colors
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

info()    { echo -e "${BOLD}${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${BOLD}${YELLOW}⚠${RESET} $1"; }
error()   { echo -e "${BOLD}${RED}✗${RESET} $1"; exit 1; }

echo ""
echo -e "${BOLD}SwiftGenerator — Bootstrap${RESET}"
echo "─────────────────────────────────────"
echo ""

# ── 1. Check mise ─────────────────────────

if ! command -v mise &>/dev/null; then
	warn "mise is not installed."
	echo ""
	echo "  Install it with:"
	echo "    curl https://mise.jdx.dev/install.sh | sh"
	echo ""
	echo "  Then activate it in your shell (~/.zshrc or ~/.bashrc):"
	echo "    eval \"\$(~/.local/bin/mise activate zsh)\""
	echo ""
	error "Run this script again after installing mise."
fi

info "mise found: $(mise --version)"

# ── 2. Trust the project ──────────────────

echo ""
echo "Setting up mise trust for this project..."
mise trust 2>/dev/null || true
info "Project trusted by mise"

# ── 3. Install tools ──────────────────────

echo ""
echo "Installing tools defined in mise.toml..."
mise install
info "Tools installed"

# ── 4. Verify Tuist ──────────────────────

if ! mise which tuist &>/dev/null; then
	error "tuist is not available via mise. Check your mise.toml."
fi

info "tuist $(mise exec -- tuist version) available"

# ── 5. Generate Xcode project ─────────────

echo ""
echo "Installing project dependencies..."
mise exec -- tuist install 2>/dev/null || true
info "Dependencies installed"

echo ""
echo "Generating Xcode project..."
mise exec -- tuist generate
info "Xcode project generated"

# ── Done ──────────────────────────────────

echo ""
echo "─────────────────────────────────────"
echo -e "${BOLD}${GREEN}Done!${RESET} Open the .xcworkspace in Xcode."
echo ""
echo "  Useful commands:"
echo "    make build          → Build the project"
echo "    make test           → Run tests"
echo "    make release        → Build universal binary"
echo "    mise run generate   → Regenerate project"
echo "    mise run edit       → Edit Tuist manifests"
echo ""
