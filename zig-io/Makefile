MDBOOK ?= mdbook
ZIG ?= zig

.DEFAULT_GOAL := test

.PHONY: book-build serve test clean test-examples

book-build:
	$(MDBOOK) build

serve:
	$(MDBOOK) serve --open

test-examples:
	@echo "===> Testing example 01-file-io"
	cd examples/01-file-io && $(ZIG) build run && $(ZIG) build test
	@echo "===> Testing example 02-streaming"
	cd examples/02-streaming && $(ZIG) build run && $(ZIG) build test
	@echo "===> Testing example 03-fiber-concurrent"
	cd examples/03-fiber-concurrent && $(ZIG) build run && $(ZIG) build test
	@echo "===> All examples passed successfully!"

test: book-build test-examples

clean:
	$(MDBOOK) clean
