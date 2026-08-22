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
