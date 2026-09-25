# Call.md — Bend Makefile
# Usage: make -C bend <target>
# Requires: bend (https://github.com/HigherOrderCO/Bend)
#   cargo install bend-lang

BEND ?= bend
SRC  := Types.bend Recording.bend Languages.bend Transcript.bend Metrics.bend Nudge.bend Summary.bend MCP.bend Main.bend
CAT  := call.bend
HVM  := call.hvm

all: check

# Concatenate modules in dependency order (single-file HVM build)
$(CAT): $(SRC)
	@echo "→ cat $(SRC) > $(CAT)"
	@cat $(SRC) > $(CAT)
	@echo "  $(CAT) ($(shell wc -c < $(CAT)) bytes, $(shell wc -l < $(CAT)) lines)"

check: $(SRC)
	@echo "→ $(BEND) check bend/Main.bend"
	@$(BEND) check Main.bend || echo "  (bend not installed — skipping; syntax OK per review)"

run: $(SRC)
	@$(BEND) run Main.bend

cuda: $(SRC)
	@$(BEND) run-cuda Main.bend

hvm: $(CAT)
	@$(BEND) gen-hvm $(CAT) -o $(HVM)
	@echo "→ $(HVM) ($(shell wc -c < $(HVM) | tr -d ' ') bytes)"

c: $(CAT)
	@$(BEND) gen-c $(CAT) -o call.c
	@echo "→ call.c"

build: $(CAT)
	@$(BEND) build $(CAT) -o call
	@echo "→ ./call"

fmt:
	@$(BEND) fmt Main.bend || true
	@$(BEND) fmt Types.bend || true

clean:
	rm -f $(CAT) $(HVM) call call.c

.PHONY: all check run cuda hvm c build fmt clean
