# Force bash so recipes using `set -o pipefail` work on systems where /bin/sh
# is dash (Debian/Ubuntu CI runners).
SHELL := /bin/bash

.PHONY: all ci precommit compile fmt \
	check check-dirty check-fmt check-lint check-hank check-xref check-dialyzer \
	test cover doc clean

all: ci

ci:
	$(MAKE) compile
	$(MAKE) check-dirty
	$(MAKE) check
	$(MAKE) test
	$(MAKE) cover
	$(MAKE) doc

precommit:
	$(MAKE) fmt
	$(MAKE) compile
	$(MAKE) check-fmt
	$(MAKE) check-lint
	$(MAKE) test

compile:
	rebar3 compile
	rebar3 as test compile

fmt:
	rebar3 fmt

check: check-fmt check-lint check-hank check-xref check-dialyzer

check-dirty:
	@git diff --quiet || (echo "Error: uncommitted changes after build" && git diff --name-only && exit 1)

check-fmt:
	rebar3 fmt --check

check-lint:
	rebar3 lint

check-hank:
	@# Capture instead of `tee`: a redirected log opened O_TRUNC by tee loses
	@# everything logged before. Fails on any finding and on a stale ignore,
	@# which hank only warns about.
	@out=$$(rebar3 hank 2>&1); status=$$?; printf '%s\n' "$$out"; \
		[ $$status -eq 0 ] && ! printf '%s\n' "$$out" | grep -q "no longer needed"

check-xref:
	rebar3 xref

check-dialyzer:
	rebar3 as test dialyzer

test:
	rebar3 as test test

cover:
	rebar3 as test check_cover

doc:
	rebar3 compile
	@set -o pipefail; out=$$(rebar3 doc 2>&1); printf '%s\n' "$$out"; \
		printf '%s\n' "$$out" | (! grep -q "warning")

clean:
	rebar3 clean -a
	rm -rf _build doc
