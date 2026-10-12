.PHONY: install update format lint test parity clean

TEMP_DIR := $(CURDIR)/temp
export TMPDIR := $(TEMP_DIR)
export CRYSTAL_CACHE_DIR := $(TEMP_DIR)/crystal-cache
PARITY_SKILL_DIR ?= $(HOME)/.agents/skills/crystal_forge/skills/cross-language-crystal-parity
PARITY_DISCOVER ?= $(shell command -v chiasmus-discover 2>/dev/null)
PARITY_GRAMMARS ?= $(PARITY_SKILL_DIR)/bin/darwin-aarch64/grammars

$(TEMP_DIR):
	mkdir -p "$@"

install: | $(TEMP_DIR)
	shards install

update: | $(TEMP_DIR)
	shards update

format: | $(TEMP_DIR)
	crystal tool format src spec

lint: | $(TEMP_DIR)
	ameba src spec

test: | $(TEMP_DIR)
	crystal spec

parity: | $(TEMP_DIR)
	@test -x "$(PARITY_DISCOVER)" || { echo "Install a compatible chiasmus-discover or set PARITY_DISCOVER" >&2; exit 1; }
	@test -d "$(PARITY_GRAMMARS)" || { echo "Set PARITY_GRAMMARS to the Rust grammar bundle" >&2; exit 1; }
	CHIASMUS_DISCOVER_BIN="$(PARITY_DISCOVER)" CHIASMUS_GRAMMAR_DIR="$(PARITY_GRAMMARS)" PORT_SCOPE_INCLUDE=src PORT_PARSER=tree-sitter "$(PARITY_SKILL_DIR)/scripts/check_port_inventory.sh" . plans/inventory/rust_port_inventory.tsv vendor/regex/regex-automata rust
	CHIASMUS_DISCOVER_BIN="$(PARITY_DISCOVER)" CHIASMUS_GRAMMAR_DIR="$(PARITY_GRAMMARS)" PORT_SCOPE_INCLUDE=src PORT_PARSER=tree-sitter "$(PARITY_SKILL_DIR)/scripts/check_source_parity.sh" . plans/inventory/rust_source_parity.tsv vendor/regex/regex-automata rust
	PORT_SCOPE_INCLUDE=src,tests PORT_PARSER=regex "$(PARITY_SKILL_DIR)/scripts/check_test_parity.sh" . plans/inventory/rust_test_parity.tsv vendor/regex/regex-automata rust

clean:
	rm -rf -- ./temp
