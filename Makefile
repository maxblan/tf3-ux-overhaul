# Transport Fever 3 mod (from tf3-mod-template; rename with tools/init.sh)
#
# Run `make` for the list of targets. Targets that touch the game need WSL with access to the
# Windows Steam installation (see README.md).

MOD        := ux_overhaul
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
LUA_FILES  := $(shell find src spec tools/lua -name '*.lua' -not -path '*/node_modules/*' -not -path '*/vendor/*')

.DEFAULT_GOAL := help
.PHONY: help deps test lint test-ingame check content preview deploy validate undeploy package clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

deps: ## Install the tooling (fengari, luacheck source, SVG renderer)
	cd $(LUA_TOOLS) && $(NPM) ci
	cd tools/preview && $(NPM) ci
	rm -rf $(LUA_TOOLS)/vendor/luacheck && mkdir -p $(LUA_TOOLS)/vendor/luacheck
	curl -sSL https://github.com/lunarmodules/luacheck/archive/refs/tags/v$(LUACHECK_VERSION).tar.gz \
		| tar xz --strip-components=1 -C $(LUA_TOOLS)/vendor/luacheck

test: ## Run the offline specs (spec/*_spec.lua)
ifneq ($(BUSTED),)
	"$(BUSTED)"
else
	@test -d $(LUA_TOOLS)/node_modules || { echo "run 'make deps' first"; exit 1; }
	"$(NODE)" $(LUA_TOOLS)/run_specs.js
endif

lint: ## Run luacheck on src, spec and tools/lua
ifneq ($(LUACHECK),)
	"$(LUACHECK)" $(LUA_FILES)
else
	@test -d $(LUA_TOOLS)/vendor/luacheck || { echo "run 'make deps' first"; exit 1; }
	"$(NODE)" $(LUA_TOOLS)/run.js $(LUA_TOOLS)/lint.lua $(LUA_FILES)
endif

test-ingame: content ## Run the in-game scenarios (launches the game)
	spec/ingame/run.sh

check: lint test test-ingame ## Run lint and all tests

content: ## Regenerate the _content.json file lists of the mod and the testbench
	tools/content_index.sh $(MOD_DIR) $(TESTBENCH)

preview: ## Render assets/preview.svg to the mod's preview image
	"$(NODE)" tools/preview/render.js assets/preview.svg $(MOD_DIR)/_metadata/0.png

deploy: content ## Copy the mod into the game's staging area
	tools/deploy.sh $(MOD_DIR)

validate: deploy ## Run the game's mod validation (launches the game briefly)
	tools/validate.sh $(MOD)

undeploy: ## Remove the mod and the testbench from the staging area
	tools/deploy.sh --remove $(MOD_DIR) $(TESTBENCH)

package: content preview ## Build the upload zip in dist/
	@mkdir -p $(DIST)
	@rm -f $(DIST)/$(MOD).zip
	cd src && python3 -m zipfile -c ../$(DIST)/$(MOD).zip $(MOD)
	@echo "built $(DIST)/$(MOD).zip"

clean: ## Remove build output and in-game test logs
	rm -rf $(DIST) spec/ingame/results spec/ingame/last_run.txt
