MDBOOK ?= mdbook
ZIG ?= zig

.DEFAULT_GOAL := test

.PHONY: book-build serve test clean test-examples

book-build:
	$(MDBOOK) build

serve:
	$(MDBOOK) serve --open

test-examples:
	@echo "===> Testing 01-zig-app"
	cd examples/01-zig-app && $(ZIG) build run && $(ZIG) build test
	@echo "===> Testing 02-mixed-c-zig"
	cd examples/02-mixed-c-zig && $(ZIG) build run
	@echo "===> Testing 03-code-generation"
	cd examples/03-code-generation && $(ZIG) build run && $(ZIG) build test
	@echo "===> Testing 04-c-library-port"
	cd examples/04-c-library-port && $(ZIG) build test
	@echo "===> Testing 05-custom-step"
	cd examples/05-custom-step && $(ZIG) build pack && $(ZIG) build run
	@echo "===> All examples passed successfully!"

test: book-build test-examples

clean:
	$(MDBOOK) clean
