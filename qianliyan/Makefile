.PHONY: all core test macos run dist wasm web clean

all: core macos

core:
	zig build

test:
	zig build test --summary all

macos: core
	cd macos && swift build

run: core
	cd macos && swift run

dist:
	bash scripts/package.sh

wasm:
	zig build wasm
	cp -f zig-out/web/qianliyan.wasm web/qianliyan.wasm
	mkdir -p ../docs/qianliyan
	cp -f zig-out/web/qianliyan.wasm ../docs/qianliyan/qianliyan.wasm

web: wasm
	@echo "Serving Qianliyan Web at http://localhost:8000"
	python3 -m http.server 8000 --directory web

clean:
	rm -rf zig-out .zig-cache dist macos/.build
	cd macos && swift package reset
