DEPLOY_HOST = 23.92.26.189
DEPLOY_PATH = akuaku.org/firmament/
HTML_PORT ?= 8766
ARCHIVE_PATH = /tmp/Firmament.xcarchive

.PHONY: deploy-html-only local-html-server archive archive-only bump-build

# Deploy the contents of html/ to the remote. `rsync --chmod` enforces
# correct file and directory modes on every transfer regardless of the
# local umask, so www-data can always read and descend into the dir.
# (Same recipe as Archivista — see that Makefile for the mode breakdown.)
deploy-html-only:
	@echo "→ Deploying html/ to $(DEPLOY_HOST)..."
	rsync -av --chmod=Du=rwx,Dg=rxs,Do=rx,Fu=rw,Fg=r,Fo=r \
		html/ $(DEPLOY_HOST):$(DEPLOY_PATH)
	@echo "✓ Deployed to $(DEPLOY_HOST):$(DEPLOY_PATH)"

# Serve html/ locally to iterate on copy/styling before deploying.
local-html-server:
	@echo "→ Serving html/ at http://localhost:$(HTML_PORT)/"
	@echo "  (Ctrl-C to stop)"
	@cd html && python3 -m http.server $(HTML_PORT)

# Increment the build number (CURRENT_PROJECT_VERSION) in project.yml. This is
# the source of truth because xcodegen regenerates App/Info.plist on every run,
# which would otherwise reset CFBundleVersion. App Store Connect rejects a
# re-upload with a duplicate build number, so every archive needs a fresh one.
bump-build:
	@current=$$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/[^0-9]*//g'); \
	next=$$(( current + 1 )); \
	sed -i '' "s/CURRENT_PROJECT_VERSION: $$current/CURRENT_PROJECT_VERSION: $$next/" project.yml; \
	echo "→ Build number: $$current → $$next"

# Build a Release archive for App Store submission. Bumps the build number,
# regenerates the project so the new number lands in Info.plist, then archives.
# Upload the result from the Xcode Organizer (Window → Organizer → Archives →
# Distribute App), which handles App Store Connect auth and signing.
#
# Auto-incrementing means a failed archive still consumes a build number; the
# gap is harmless (App Store Connect only requires numbers to increase). To
# archive WITHOUT bumping (e.g. a retry), run `make archive-only`.
archive: bump-build archive-only

archive-only:
	xcodegen generate
	rm -rf $(ARCHIVE_PATH)
	set -o pipefail && xcodebuild archive \
		-project Firmament.xcodeproj \
		-scheme Firmament \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE_PATH) \
		2>&1 | tee /tmp/xcodebuild-archive.log
	@echo "✓ Archive at $(ARCHIVE_PATH)"
	@echo "  Next: open it in Organizer with:  open $(ARCHIVE_PATH)"
