# Build and release targets for Firmament. The work is all in the shared
# toolkit; this file only says what is different about this project.
# Run `make` for the target list, and see apple-release/README.md for the
# full set of configuration variables.
#
# LINT_DIRS is left at its default of "." — .swiftlint.yml already excludes
# FirmamentCore/.build and the generated project, so linting the repo is right.

APP_NAME = Firmament

# The App Store listing's name, which is not the project's. Only `make
# create-app` reads it, but it is the one place the two names are written down
# together, so it is worth stating rather than leaving to a wrong default.
APP_STORE_NAME = Dav's Celestial Firmament

# The App Store listing's support and privacy-policy URLs are served from html/.
# Set before the include: `help` tests DEPLOY_PATH with ifneq, which make
# evaluates while parsing.
DEPLOY_PATH = akuaku.org/firmament/

include $(HOME)/code/ProjectTemplates/apple-release/release.mk

# --- Marketing site ----------------------------------------------------------
# akuaku.org is fronted by Cloudflare, which caches static assets by URL for
# four hours. Redeploying firmament.css under an unchanged name therefore
# leaves visitors on the previous copy until that lapses — the landing page
# went out once with its new markup and its old stylesheet, which reads as a
# broken page rather than a stale one. Stamping each link with a hash of the
# file's own contents makes a changed file a different URL that no cache can
# confuse for the old one, and leaves unchanged files alone so their caching
# still counts for something.
#
# Attached to release.mk's deploy-html as a bare prerequisite: a rule with no
# recipe adds prerequisites to the target rather than replacing its recipe, so
# the shared rsync still does the work.
.PHONY: stamp-html
stamp-html:
	@python3 Scripts/stamp-html-assets.py $(HTML_DIR)

deploy-html: stamp-html

help::
	@echo "  make stamp-html         Re-stamp $(HTML_DIR)/ asset links (deploy-html does this)"
