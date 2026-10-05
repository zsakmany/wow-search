# Seek developer commands. Run them from the project root.
#   make setup   install Lua 5.1, LuaRocks, busted and luacheck into .tools/
#   make check   run luacheck and the busted tests
#   make link    symlink the Seek/ addon folder into WoW's AddOns folder
#   make link-probe  symlink the throwaway SecureOpenProbe prototype (issue #39)
#                    into the same AddOns folder

TOOLS := .tools
BIN   := $(TOOLS)/lua/bin

HEREROCKS_VERSION := 0.25.1
LUAROCKS_VERSION  := 3.8.0
BUSTED_VERSION    := 2.3.0-1
LUACHECK_VERSION  := 1.2.0-1

# The WoW Forever beta. Override for another install, for example:
#   make link WOW_ADDONS="/Applications/World of Warcraft/_forever_/Interface/AddOns"
WOW_ADDONS ?= /Applications/World of Warcraft/_classic_beta_/Interface/AddOns

.PHONY: setup check lint test link link-probe

setup:
	@case "$(CURDIR)" in *" "*) \
		echo "error: the project path contains a space: $(CURDIR)" >&2; \
		echo "LuaRocks cannot be installed there. Move the project to a path without spaces." >&2; \
		exit 1;; \
	esac
	python3 -m venv $(TOOLS)/venv
	$(TOOLS)/venv/bin/pip install --quiet --disable-pip-version-check hererocks==$(HEREROCKS_VERSION)
	$(TOOLS)/venv/bin/hererocks $(TOOLS)/lua --lua 5.1 --luarocks $(LUAROCKS_VERSION) --no-readline
	$(BIN)/luarocks install busted $(BUSTED_VERSION)
	$(BIN)/luarocks install luacheck $(LUACHECK_VERSION)

check: lint test

lint:
	$(BIN)/luacheck .

test:
	$(BIN)/busted

link:
	@test -d "$(WOW_ADDONS)" || { echo "error: no AddOns folder at $(WOW_ADDONS). Set WOW_ADDONS." >&2; exit 1; }
	@if [ -L "$(WOW_ADDONS)/Seek" ] && [ "$$(readlink "$(WOW_ADDONS)/Seek")" = "$(CURDIR)/Seek" ]; then \
		echo "already linked: $(WOW_ADDONS)/Seek -> $(CURDIR)/Seek"; \
	elif [ -e "$(WOW_ADDONS)/Seek" ] || [ -L "$(WOW_ADDONS)/Seek" ]; then \
		echo "error: $(WOW_ADDONS)/Seek already exists and is not a link to this project. Remove it first." >&2; exit 1; \
	else \
		ln -s "$(CURDIR)/Seek" "$(WOW_ADDONS)/Seek" && echo "linked: $(WOW_ADDONS)/Seek -> $(CURDIR)/Seek"; \
	fi

# The throwaway research prototype for issue #39 (prototypes/SecureOpenProbe/).
# Same AddOns folder and same "never replace" rule as `make link`.
PROBE := SecureOpenProbe

link-probe:
	@test -d "$(WOW_ADDONS)" || { echo "error: no AddOns folder at $(WOW_ADDONS). Set WOW_ADDONS." >&2; exit 1; }
	@if [ -L "$(WOW_ADDONS)/$(PROBE)" ] && [ "$$(readlink "$(WOW_ADDONS)/$(PROBE)")" = "$(CURDIR)/prototypes/$(PROBE)" ]; then \
		echo "already linked: $(WOW_ADDONS)/$(PROBE) -> $(CURDIR)/prototypes/$(PROBE)"; \
	elif [ -e "$(WOW_ADDONS)/$(PROBE)" ] || [ -L "$(WOW_ADDONS)/$(PROBE)" ]; then \
		echo "error: $(WOW_ADDONS)/$(PROBE) already exists and is not a link to this project. Remove it first." >&2; exit 1; \
	else \
		ln -s "$(CURDIR)/prototypes/$(PROBE)" "$(WOW_ADDONS)/$(PROBE)" && echo "linked: $(WOW_ADDONS)/$(PROBE) -> $(CURDIR)/prototypes/$(PROBE)"; \
	fi
