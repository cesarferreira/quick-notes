INSTALL_DIR ?= /Applications

.PHONY: build run test package install clean
build:
	swift build
run:
	swift run quick-notes
test:
	swift test
package:
	./scripts/package.sh
install: package
	@osascript -e 'if application id "dev.cesar.quicknotes" is running then' \
		-e 'tell application id "dev.cesar.quicknotes" to quit' -e 'end if'
	@mkdir -p "$(INSTALL_DIR)"
	@ditto "dist/Quick Notes.app" "$(INSTALL_DIR)/Quick Notes.app"
	@open "$(INSTALL_DIR)/Quick Notes.app"
clean:
	swift package clean
	rm -rf dist
