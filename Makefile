# Prefer the user LuaRocks launcher when present; otherwise resolve from PATH.
# BUSTED can still be set explicitly on the command line or in the environment.
BUSTED ?= $(if $(wildcard $(HOME)/.luarocks/bin/busted),$(HOME)/.luarocks/bin/busted,busted)
# nlua runs Neovim as a Lua interpreter, which lets busted run inside it.
NLUA ?= $(if $(wildcard $(HOME)/.luarocks/bin/nlua),$(HOME)/.luarocks/bin/nlua,nlua)
LUAROCKS ?= luarocks
SELENE ?= selene

.PHONY: check test test-nvim lint

check: test test-nvim lint

test:
	$(BUSTED)

# The *_nvim_spec.lua files: busted, with Neovim as its interpreter. busted
# starts under plain Lua and runs itself again under nlua, which finds
# busted's modules through the paths luarocks names. nlua runs whatever is
# on a stdin that is no terminal as Lua once the specs are done, so it gets
# an empty one. Each file gets a Neovim of its own: a spec sets the plugin
# up, replaces vim.notify and opens windows as it needs, and the next one
# starts clean. The state directory is a temporary one, so a spec that opens
# the tutor saves its place there and leaves the reader's own alone.
test-nvim:
	@eval "$$($(LUAROCKS) --lua-version 5.1 path)" && \
	export XDG_STATE_HOME="$$(mktemp -d)" && \
	for spec in spec/*_nvim_spec.lua; do \
		echo "$$spec"; \
		$(BUSTED) --run=nvim --lua=$(NLUA) "$$spec" </dev/null || exit 1; \
	done

# Lints the source tree. spec/ is excluded: it uses busted's describe/it/assert
# DSL, which selene's lua/neovim std library does not model.
lint:
	$(SELENE) lua
