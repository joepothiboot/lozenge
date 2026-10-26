build:
	stack build

test:
	stack test

fmt:
	fourmolu -i src app test

lint:
	hlint src app test

.PHONY: build test fmt lint
