.PHONY: verify

verify:
	dart format --output=none --set-exit-if-changed .
	flutter analyze
	flutter test
