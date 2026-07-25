# iphone-control - build & test targets
.PHONY: test test-shell test-mcp lint build build-helpers build-mcp

# Run all tests
test: test-shell test-mcp

# Run bats shell tests
test-shell:
	@echo "=== Running shell tests (bats) ==="
	bats tests/*.bats

# Run MCP server tests
test-mcp:
	@echo "=== Running MCP server tests ==="
	cd mcp-server && npx vitest run

# Lint all shell scripts with shellcheck
# helpers/common.sh is intentionally excluded as a standalone target: it is a
# sourced-only library, so checking it in isolation flags every constant as
# unused. -x pulls it into each script's analysis via source, where real usage
# is visible.
lint:
	@echo "=== Linting shell scripts ==="
	shellcheck -x *.sh

# Build everything
build: build-helpers build-mcp

# Compile Swift helpers
build-helpers:
	@echo "=== Compiling Swift helpers ==="
	swiftc -O helpers/get-window-id.swift -o helpers/get-window-id

# Build MCP server TypeScript
build-mcp:
	@echo "=== Building MCP server ==="
	cd mcp-server && npm run build
