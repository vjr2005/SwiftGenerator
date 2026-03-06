.DEFAULT_GOAL := help

# ───────────────────────────────────────────────────
# Bootstrap & Setup
# ───────────────────────────────────────────────────

.PHONY: bootstrap
bootstrap: ## First-time setup: install tools and generate project
	@./scripts/bootstrap.sh

.PHONY: setup
setup: ## Install dependencies and generate Xcode project
	@mise exec -- tuist install && mise exec -- tuist generate

# ───────────────────────────────────────────────────
# Tuist
# ───────────────────────────────────────────────────

.PHONY: generate
generate: ## Generate Xcode project
	@mise exec -- tuist generate

.PHONY: edit
edit: ## Open Tuist manifests for editing
	@mise exec -- tuist edit

.PHONY: build
build: ## Build with Tuist
	@mise exec -- tuist build

.PHONY: test
test: ## Run tests with Tuist
	@mise exec -- tuist test

.PHONY: clean
clean: ## Clean build artifacts
	@mise exec -- tuist clean
	@rm -rf .build build *.xcodeproj *.xcworkspace Derived/

.PHONY: graph
graph: ## Generate dependency graph
	@mise exec -- tuist graph

# ───────────────────────────────────────────────────
# Swift Package Manager
# ───────────────────────────────────────────────────

.PHONY: spm-build
spm-build: ## Build with SPM
	@swift build

.PHONY: spm-test
spm-test: ## Run tests with SPM
	@swift test

# ───────────────────────────────────────────────────
# Release
# ───────────────────────────────────────────────────

.PHONY: release
release: ## Build universal macOS binary for distribution
	@./scripts/build-release.sh

# ───────────────────────────────────────────────────
# Help
# ───────────────────────────────────────────────────

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
