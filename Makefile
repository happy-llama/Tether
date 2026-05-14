APP      = BLELock
BUNDLE   = $(APP).app
RELEASE  = .build/release/$(APP)

.PHONY: app install clean

app:
	swift build -c release
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(RELEASE)"  "$(BUNDLE)/Contents/MacOS/$(APP)"
	cp Info.plist    "$(BUNDLE)/Contents/Info.plist"
	cp -r Localization/. "$(BUNDLE)/Contents/Resources/"

install: app
	rm -rf "/Applications/$(BUNDLE)"
	cp -r "$(BUNDLE)" "/Applications/"
	@echo "Installed to /Applications/$(BUNDLE)"

clean:
	rm -rf "$(BUNDLE)" .build
