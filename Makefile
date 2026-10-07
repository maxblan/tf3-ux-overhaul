# Transport Fever 3 mod (from tf3-mod-template; rename with tools/init.sh)
#
# Run `make` for the list of targets. Targets that touch the game need WSL with access to the
# Windows Steam installation (see README.md).

MOD        := ui_overhaul
MOD_DIR    := src/$(MOD)
TESTBENCH  := spec/ingame/$(MOD)_testbench
DIST       := dist

# Busted and luacheck are used when installed; otherwise specs and lint run on fengari (Lua 5.3
# in node, see tools/lua/).
BUSTED     ?= $(shell command -v busted 2>/dev/null)
LUACHECK   ?= $(shell command -v luacheck 2>/dev/null)
NODE       ?= $(shell command -v node 2>/dev/null || command -v node.exe 2>/dev/null)
NPM        ?= $(shell command -v npm.cmd >/dev/null 2>&1 && echo "cmd.exe /c npm" || echo npm)
LUA_TOOLS  := tools/lua
LUACHECK_VERSION := 1.2.0
# The Lua Language Server type-checks with .luarc.json. Used when installed; otherwise `make deps`
# downloads it to tools/luals/server.
LUALS_VERSION := 3.19.1
LUALS      ?= $(or $(shell command -v lua-language-server 2>/dev/null),tools/luals/server/bin/lua-language-server)
LUA_FILES  := $(shell find src spec tools/lua -name '*.lua' -not -path '*/node_modules/*' -not -path '*/vendor/*')

.DEFAULT_GOAL := help
.PHONY: help deps test lint typecheck test-ingame check content preview gallery deploy validate undeploy package clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

deps: ## Install the tooling (fengari, luacheck source, Lua Language Server, SVG renderer)
	cd $(LUA_TOOLS) && $(NPM) ci
	cd tools/preview && $(NPM) ci
	rm -rf $(LUA_TOOLS)/vendor/luacheck && mkdir -p $(LUA_TOOLS)/vendor/luacheck
	curl -sSL https://github.com/lunarmodules/luacheck/archive/refs/tags/v$(LUACHECK_VERSION).tar.gz \
		| tar xz --strip-components=1 -C $(LUA_TOOLS)/vendor/luacheck
	rm -rf tools/luals/server && mkdir -p tools/luals/server
	curl -sSL https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/lua-language-server-$(LUALS_VERSION)-linux-x64.tar.gz \
		| tar xz -C tools/luals/server

test: ## Run the offline specs (spec/*_spec.lua)
ifneq ($(BUSTED),)
	"$(BUSTED)"
else
	@test -d $(LUA_TOOLS)/node_modules || { echo "run 'make deps' first"; exit 1; }
	"$(NODE)" $(LUA_TOOLS)/run_specs.js
endif

lint: ## Run luacheck on src, spec and tools/lua, and reject syntax the game's Lua 5.2 lacks
	@# Full-line comments are skipped: type annotations such as table<K, table<K2, V>> never reach Lua.
	@! grep -rnE --include='*.lua' '\\u\{|[^-/]//[^/]|[^~]~[^=]|<<|>>' src | grep -vE '^[^:]+:[0-9]+:[[:space:]]*--' \
		|| { echo "Lua 5.3 syntax above (\\u{} escape, //, bitwise ops): the game embeds Lua 5.2"; exit 1; }
	@! grep -rn --include='*.lua' 'return react.CallOriginalRecipe' src \
		|| { echo "wrap CallOriginalRecipe in a layout: a recipe's root must be a layout (else the game UI drops)"; exit 1; }
	@! grep -rnE --include='*.lua' '\blayout = ([a-z_]+\.)?[A-Z][A-Za-z_]*[{(]' src | grep -v 'layout = builtin\.' \
		|| { echo "a Component's layout must be a builtin layout, not a recipe: the game crashes natively (observed in game)"; exit 1; }
	@! grep -rnE --include='*.lua' '\braw(get|set|equal|len)\(' src | grep -vE '^[^:]+:[0-9]+:[[:space:]]*--' \
		|| { echo "rawget/rawset/rawequal/rawlen are not there in the game's GUI Lua state (observed in game)"; exit 1; }
ifneq ($(LUACHECK),)
	"$(LUACHECK)" $(LUA_FILES)
else
	@test -d $(LUA_TOOLS)/vendor/luacheck || { echo "run 'make deps' first"; exit 1; }
	"$(NODE)" $(LUA_TOOLS)/run.js $(LUA_TOOLS)/lint.lua $(LUA_FILES)
endif

typecheck: ## Type-check all Lua files with the Lua Language Server (strict, see .luarc.json)
	@test -x "$(LUALS)" || { echo "run 'make deps' first"; exit 1; }
	"$(LUALS)" --check . --checklevel=Warning --trust_all_plugins --logpath=.lua-check

test-ingame: content ## Run the in-game scenarios (launches the game; SAVE="name" runs on a copy of that savegame; WITH="mod_a mod_b" adds installed mods, MODS_FIRST=1 before this one; WITHOUT="mod_c" leaves the savegame's mods out; ONLY="check_a check_b" runs just those GUI checks; OFF="feature_a" switches those features off; WINDOW=1280x720 FONT=LARGE UI_SCALE=1.5 for other screens)
	spec/ingame/run.sh $(if $(SAVE),--save "$(SAVE)") $(foreach m,$(WITH),--with-mod $(m)) $(foreach m,$(WITHOUT),--without-mod $(m)) $(if $(filter-out 0,$(MODS_FIRST)),--mods-first) $(foreach c,$(ONLY),--only $(c)) $(foreach f,$(OFF),--off $(f)) $(if $(WINDOW),--window $(WINDOW)) $(if $(FONT),--font $(FONT)) $(if $(UI_SCALE),--ui-scale $(UI_SCALE)) $(if $(filter-out 0,$(NO_SHOTS)),--no-shots)

check: lint typecheck test test-ingame ## Run lint, the type check and all tests

content: ## Regenerate gui/needs.lua (what each feature takes from the game) and the _content.json file lists
	python3 tools/needs.py
	tools/content_index.sh $(MOD_DIR) $(TESTBENCH)

preview: ## Render assets/preview.svg to the mod's preview image
	"$(NODE)" tools/preview/render.js assets/preview.svg $(MOD_DIR)/_metadata/0.png

deploy: content ## Copy the mod into the game's staging area
	tools/deploy.sh $(MOD_DIR)

validate: deploy ## Run the game's mod validation (launches the game briefly)
	tools/validate.sh $(MOD)

undeploy: ## Remove the mod and the testbench from the staging area
	tools/deploy.sh --remove $(MOD_DIR) $(TESTBENCH)

gallery: ## Compose the mod.io gallery cards (src/ui_overhaul/_metadata/1.png ...) (screenshots first: see docs/gallery.md)
	tools/gallery/build.sh

package: content preview ## Build the upload zip in dist/
	@mkdir -p $(DIST)
	@rm -f $(DIST)/$(MOD).zip
	cd src && python3 -m zipfile -c ../$(DIST)/$(MOD).zip $(MOD)
	@echo "built $(DIST)/$(MOD).zip"

clean: ## Remove build output and in-game test logs
	rm -rf $(DIST) spec/ingame/results spec/ingame/last_run.txt
