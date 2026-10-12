.PHONY: install update format lint test clean

TEMP_DIR := $(CURDIR)/temp
export TMPDIR := $(TEMP_DIR)
export CRYSTAL_CACHE_DIR := $(TEMP_DIR)/crystal-cache

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

clean:
	rm -rf -- ./temp
