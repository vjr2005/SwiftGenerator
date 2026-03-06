#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   SwiftGenerator — Bootstrap Setup   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

# ─── Step 1: Check mise ───────────────────────────
info "Checking for mise..."
if ! command -v mise &> /dev/null; then
	error "mise is not installed. Install it from https://mise.jdx.dev"
fi
success "mise found: $(mise --version)"

# ─── Step 2: Trust & install tools ────────────────
info "Trusting project configuration..."
mise trust

info "Installing tools..."
mise install
success "Tools installed."

# ─── Step 3: Verify tuist ─────────────────────────
info "Verifying tuist..."
if ! command -v tuist &> /dev/null; then
	error "tuist not found after mise install. Check mise.toml configuration."
fi
success "tuist found: $(tuist version)"

# ─── Step 4: Install dependencies & generate ──────
info "Installing Tuist dependencies..."
tuist install
success "Dependencies installed."

info "Generating Xcode project..."
tuist generate
success "Xcode project generated."

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Bootstrap complete!             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "Next steps:"
echo -e "  ${BLUE}make build${NC}     — Build the project"
echo -e "  ${BLUE}make test${NC}      — Run tests"
echo -e "  ${BLUE}make release${NC}   — Build universal binary"
echo ""
