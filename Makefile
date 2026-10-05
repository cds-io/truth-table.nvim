# Prefer the user LuaRocks launcher when present; otherwise resolve from PATH.
# BUSTED can still be set explicitly on the command line or in the environment.
BUSTED ?= $(if $(wildcard $(HOME)/.luarocks/bin/busted),$(HOME)/.luarocks/bin/busted,busted)
# nlua runs Neovim as a Lua interpreter, which lets busted run inside it.
NLUA ?= $(if $(wildcard $(HOME)/.luarocks/bin/nlua),$(HOME)/.luarocks/bin/nlua,nlua)
LUAROCKS ?= luarocks
SELENE ?= selene
NVIM ?= nvim

.PHONY: check test test-nvim test-integration lint

check: test test-nvim test-integration lint

test:
	$(BUSTED)

# The *_nvim_spec.lua files: busted, with Neovim as its interpreter. busted
# starts under plain Lua and runs itself again under nlua, which finds
# busted's modules through the paths luarocks names. nlua runs whatever is
# on a stdin that is no terminal as Lua once the specs are done, so it gets
# an empty one.
test-nvim:
	eval "$$($(LUAROCKS) --lua-version 5.1 path)" && $(BUSTED) --run=nvim --lua=$(NLUA) </dev/null

test-integration:
	$(NVIM) --headless -u NONE -i NONE -l spec/integration.lua
	$(NVIM) --headless -u spec/startup.lua -i NONE
	TRUTH_TABLE_TEST_CUSTOM=1 $(NVIM) --headless -u spec/startup.lua -i NONE
	$(NVIM) --headless -u NONE -i NONE -l spec/preview.lua
	$(NVIM) --headless -u NONE -i NONE -l spec/tutor.lua
	$(NVIM) --headless -u NONE -i NONE -l spec/tutor_vellum.lua

# Lints the source tree. spec/ is excluded: it uses busted's describe/it/assert
# DSL, which selene's lua/neovim std library does not model.
lint:
	$(SELENE) lua
