APP_NAME := LightSnap
DIST_DIR := dist
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app
APP_ZIP := $(DIST_DIR)/$(APP_NAME).zip

# Universal binary (Apple Silicon + Intel). Override with `make ARCH_FLAGS=`
# to build only for the host architecture.
ARCH_FLAGS ?= --arch arm64 --arch x86_64

# Code signing identity. The default ad-hoc signature ("-") runs fine on the
# Mac that built it, but Gatekeeper blocks downloaded copies. For distribution
# use a Developer ID Application identity, e.g.
#   make release SIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID99)"
SIGN_IDENTITY ?= -

# Keychain profile for notarytool, created once with:
#   xcrun notarytool store-credentials lightsnap \
#     --apple-id you@example.com --team-id TEAMID99 --password <app-specific-password>
NOTARY_PROFILE ?= lightsnap

ifeq ($(strip $(SIGN_IDENTITY)),-)
CODESIGN_ARGS := --force --options runtime --sign -
else
CODESIGN_ARGS := --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)"
endif

.PHONY: all build app zip release run clean

all: app

build:
	swift build -c release $(ARCH_FLAGS)

app: build
	@BIN_PATH="$$(swift build -c release $(ARCH_FLAGS) --show-bin-path)"; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"; \
	cp "$$BIN_PATH/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	cp Support/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"; \
	codesign $(CODESIGN_ARGS) "$(APP_BUNDLE)"; \
	echo "Built $(APP_BUNDLE)"

# ditto preserves the signature, permissions, and symlinks — plain `zip` or
# CI artifact upload of the bare .app does not.
zip: app
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(APP_ZIP)"
	@echo "Zipped $(APP_ZIP)"

# Sign with a Developer ID, notarize with Apple, staple the ticket, and
# re-zip a Gatekeeper-clean archive for distribution.
release: zip
	@if [ "$(strip $(SIGN_IDENTITY))" = "-" ]; then \
		echo "error: set SIGN_IDENTITY to a 'Developer ID Application' identity to notarize"; \
		exit 1; \
	fi
	xcrun notarytool submit "$(APP_ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP_BUNDLE)"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(APP_ZIP)"
	@echo "Notarized and stapled: $(APP_ZIP)"

run: app
	open "$(APP_BUNDLE)"

clean:
	rm -rf .build "$(DIST_DIR)"
