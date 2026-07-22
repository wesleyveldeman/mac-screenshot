APP_NAME := LightSnap
DIST_DIR := dist
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app

# Universal binary (Apple Silicon + Intel). Override with `make ARCH_FLAGS=`
# to build only for the host architecture.
ARCH_FLAGS ?= --arch arm64 --arch x86_64

.PHONY: all build app run clean

all: app

build:
	swift build -c release $(ARCH_FLAGS)

app: build
	@BIN_PATH="$$(swift build -c release $(ARCH_FLAGS) --show-bin-path)"; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"; \
	cp "$$BIN_PATH/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	cp Support/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"; \
	codesign --force --sign - "$(APP_BUNDLE)"; \
	echo "Built $(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

clean:
	rm -rf .build "$(DIST_DIR)"
