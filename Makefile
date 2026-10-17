.PHONY: install update format lint test parity clean

TEMP_DIR := $(CURDIR)/temp
export TMPDIR := $(TEMP_DIR)
export CRYSTAL_CACHE_DIR := $(TEMP_DIR)/crystal-cache
export CHIASMUS_TOOLCHAIN_CACHE_DIR := $(TEMP_DIR)/chiasmus-toolchains
export CHIASMUS_TOOLCHAIN_OFFLINE ?= 1
PARITY_SKILL_DIR ?= $(HOME)/.agents/skills/crystal_forge/skills/cross-language-crystal-parity

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
	PORT_SCOPE_INCLUDE=src PORT_PARSER=tree-sitter "$(PARITY_SKILL_DIR)/scripts/check_port_inventory.sh" . plans/inventory/rust_port_inventory.tsv vendor/regex/regex-automata rust
	PORT_SCOPE_INCLUDE=src PORT_PARSER=tree-sitter "$(PARITY_SKILL_DIR)/scripts/check_source_parity.sh" . plans/inventory/rust_source_parity.tsv vendor/regex/regex-automata rust
	PORT_SCOPE_INCLUDE=src,tests PORT_PARSER=regex "$(PARITY_SKILL_DIR)/scripts/check_test_parity.sh" . plans/inventory/rust_test_parity.tsv vendor/regex/regex-automata rust

clean:
	rm -rf -- ./temp
