# Override if your `busted` is not the one on PATH. On this machine the Homebrew
# `busted` launcher points at a removed lua5.4; the working one lives in the
# user rocks tree:  make test BUSTED=$(HOME)/.luarocks/bin/busted
BUSTED ?= busted
SELENE ?= selene

.PHONY: test lint

test:
	$(BUSTED)

# Lints the source tree. spec/ is excluded: it uses busted's describe/it/assert
# DSL, which selene's lua/neovim std library does not model.
lint:
	$(SELENE) lua
