# Minimal helpers that delegate to scripts/xc.sh to avoid duplication.

.PHONY: build test clean

build:
	bash scripts/xc.sh build

test:
	bash scripts/xc.sh test

clean:
	rm -rf build/DerivedData build/DerivedData-beta

