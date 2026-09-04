.PHONY: build run

build:
	./scripts/build-macos.sh

run: build
	open build/CodexUsageMonitor.app
