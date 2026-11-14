.PHONY: all core test macos run dist clean

all: core macos

core:
	env -u all_proxy -u http_proxy -u https_proxy -u ALL_PROXY -u HTTP_PROXY -u HTTPS_PROXY zig build

test:
	env -u all_proxy -u http_proxy -u https_proxy -u ALL_PROXY -u HTTP_PROXY -u HTTPS_PROXY zig build test --summary all

macos: core
	cd macos && swift build

run: core
	cd macos && swift run

dist:
	bash scripts/package.sh

clean:
	rm -rf zig-out .zig-cache dist macos/.build
	cd macos && swift package reset
