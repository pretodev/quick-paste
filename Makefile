.PHONY: validate test

validate: test
	omarchy plugin validate .

test:
	node tests/clipboard-history.test.js
