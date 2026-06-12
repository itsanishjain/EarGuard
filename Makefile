APP_NAME := EarGuard
BUNDLE_ID := dev.anish.earguard
BUILD_DIR := .build/release
APP_DIR := build/$(APP_NAME).app

.PHONY: build run app install clean

build:
	swift build -c release

run:
	swift run $(APP_NAME)

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	plutil -create xml1 "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $(APP_NAME)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $(BUNDLE_ID)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleName string $(APP_NAME)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $(APP_NAME)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$(APP_DIR)/Contents/Info.plist"
	codesign --force --sign - "$(APP_DIR)"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_DIR)" /Applications/

clean:
	rm -rf .build build
