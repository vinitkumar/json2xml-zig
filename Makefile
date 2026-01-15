.PHONY: build run test fmt fmt-check clean

build:
	zig build

run:
	zig build run

test:
	zig build test

fmt:
	zig fmt .

fmt-check:
	zig fmt --check .

clean:
	rm -rf .zig-cache zig-out
