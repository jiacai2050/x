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
	mkdir -p ../docs/qianliyan/web
	cp -f web/index.html ../docs/qianliyan/web/index.html
	cp -f web/sw.js ../docs/qianliyan/web/sw.js
	cp -f web/manifest.webmanifest ../docs/qianliyan/web/manifest.webmanifest
	cp -f zig-out/web/qianliyan.wasm ../docs/qianliyan/web/qianliyan.wasm

web: wasm
	@echo "Serving Qianliyan Web at http://localhost:8000"
	python3 -m http.server 8000 --directory web

clean:
	rm -rf zig-out .zig-cache dist macos/.build
	cd macos && swift package reset
