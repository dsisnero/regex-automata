.PHONY: install update format lint test clean

TEMP_DIR := $(CURDIR)/temp
CRYSTAL_CACHE_DIR := $(TEMP_DIR)/crystal-cache

install:
	shards install

update:
	shards update

format:
	crystal tool format src spec

lint:
	ameba src spec

test:
	CRYSTAL_CACHE_DIR=$(CRYSTAL_CACHE_DIR) crystal spec

clean:
	rm -rf $(TEMP_DIR) .crystal-cache/ lib/
