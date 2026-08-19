# ClipPanel build shortcuts. The only requirement is Xcode 26 or later.

SCHEME = ClipPanel
PROJECT = ClipPanel.xcodeproj
DERIVED = build/DerivedData
APP = $(DERIVED)/Build/Products/Release/ClipPanel.app

.PHONY: build install test selftest verify clean

## Build a Release app into build/
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) build

## Build and copy into /Applications. Built locally, so Gatekeeper raises no prompt.
install: build
	@rm -rf /Applications/ClipPanel.app
	ditto "$(APP)" /Applications/ClipPanel.app
	@echo "Installed. Launch ClipPanel from /Applications; it lives in the menu bar."

## Run the unit test suite (never touches your real clipboard or keychain)
test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) test

## Build Debug and run the headless self test against the live app
selftest:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build
	CLIPPANEL_SELFTEST=1 "$(DERIVED)/Build/Products/Debug/ClipPanel.app/Contents/MacOS/ClipPanel"

## Run the security gates against the Release build
verify: build
	Scripts/audit-logging.sh
	Scripts/verify-release.sh "$(APP)"

clean:
	rm -rf build
