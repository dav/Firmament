# Build and release targets for Firmament. The work is all in the shared
# toolkit; this file only says what is different about this project.
# Run `make` for the target list, and see ios-release/README.md for the
# full set of configuration variables.
#
# LINT_DIRS is left at its default of "." — .swiftlint.yml already excludes
# FirmamentCore/.build and the generated project, so linting the repo is right.

APP_NAME = Firmament

include $(HOME)/code/ProjectTemplates/ios-release/release.mk

# --- Marketing site ----------------------------------------------------------

DEPLOY_HOST = 23.92.26.189
DEPLOY_PATH = akuaku.org/firmament/
HTML_PORT ?= 8766

.PHONY: deploy-html-only local-html-server

help::
	@echo
	@echo "Marketing site:"
	@echo "  make local-html-server   Serve html/ at http://localhost:$(HTML_PORT)/"
	@echo "  make deploy-html-only    rsync html/ to $(DEPLOY_HOST)"

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
