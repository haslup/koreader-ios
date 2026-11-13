IOS_DIR = $(PLATFORM_DIR)/ios

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
plugins/autofrontlight.koplugin
plugins/hello.koplugin
plugins/timesync.koplugin
tools
endef

# Preflight: bail out early with a single message listing every missing
# brew package + the PATH export, instead of failing one tool at a time
# during the build (see hezi/koreader-ios#1).
ios-check-prereqs:
	@$(CURDIR)/platform/ios/check-prereqs.sh

update: ios-check-prereqs all
	$(CURDIR)/platform/ios/do_ios_bundle.sh $(INSTALL_DIR)

# Per-developer signing settings live in platform/ios/local.config
# (git-ignored; see local.config.example): IOS_TEAM_ID and IOS_BUNDLE_ID.
# They're passed to xcodegen, so a regenerated KOReader.xcodeproj keeps the
# team and bundle id instead of resetting them.
-include $(IOS_DIR)/local.config

# Bundle identifier baked into Info.plist and the Xcode project.
IOS_BUNDLE_ID ?= rocks.koreader.ios
# Apple developer team ID for automatic signing (empty: pick it in Xcode).
IOS_TEAM_ID ?=

# CFBundleShortVersionString has to be a dotted numeric string; the raw
# `git describe` output (v2026.03-70-gabc123_2026-04-27) is not, and iOS
# rejects the bundle at install time. Split the describe into the tag and
# the commits-ahead count: v2026.03-70-g... -> 2026.03.70 / build 70.
# With no tags (fresh clone of this fork) `git describe` is empty; fall back
# to 0.0.<commit count> so the plist still holds a valid dotted-numeric string.
KO_VER_PARTS := $(subst -, ,$(patsubst v%,%,$(VERSION)))
ifeq ($(strip $(KO_VER_PARTS)),)
IOS_COMMIT_COUNT := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
IOS_SHORT_VERSION := 0.0.$(IOS_COMMIT_COUNT)
IOS_BUNDLE_VERSION := $(IOS_COMMIT_COUNT)
else
IOS_SHORT_VERSION := $(word 1,$(KO_VER_PARTS)).$(or $(word 2,$(KO_VER_PARTS)),0)
IOS_BUNDLE_VERSION := $(or $(word 2,$(KO_VER_PARTS)),0)
endif

# platform/ios/Info.plist is gitignored and generated. project.yml points
# INFOPLIST_FILE at it, so it must exist before xcodegen runs -- a fresh
# clone has only Info.plist.in. It's regenerated on every make run (the
# version changes with each commit) but only rewritten when its contents
# change, so Xcode doesn't see a new file on every build.
$(IOS_DIR)/Info.plist: $(IOS_DIR)/Info.plist.in FORCE
	@sed -e 's|@BUNDLE_ID@|$(IOS_BUNDLE_ID)|g' \
	     -e 's|@SHORT_VERSION@|$(IOS_SHORT_VERSION)|g' \
	     -e 's|@BUNDLE_VERSION@|$(IOS_BUNDLE_VERSION)|g' \
	     -e 's|@VERSION@|$(IOS_SHORT_VERSION)|g' \
	     $< > $@.tmp
	@if cmp -s $@.tmp $@; then rm -f $@.tmp; else \
	  mv $@.tmp $@; \
	  echo "Generated $@ (version $(IOS_SHORT_VERSION), build $(IOS_BUNDLE_VERSION), id $(IOS_BUNDLE_ID))"; \
	fi

ios-info-plist: $(IOS_DIR)/Info.plist

# Generate KOReader.xcodeproj at the repo root from platform/ios/project.yml.
# Depends on `all` so the staging tree + base/build/<machine>/libs/ exist
# (the project's pre-build script also calls `make TARGET=ios base`, but
# having them present at generation time avoids confusing first-time errors).
xcodeproj: ios-check-prereqs all $(IOS_DIR)/Info.plist
	IOS_TEAM_ID='$(IOS_TEAM_ID)' IOS_BUNDLE_ID='$(IOS_BUNDLE_ID)' \
	xcodegen generate \
		--spec $(IOS_DIR)/project.yml \
		--project $(CURDIR) \
		--project-root $(CURDIR)
	@echo
	@echo "Generated $(CURDIR)/KOReader.xcodeproj"
	@echo "Signing: team '$(IOS_TEAM_ID)', bundle id '$(IOS_BUNDLE_ID)' (platform/ios/local.config)."
	@echo "Build, install and launch on a device with platform/ios/deploy.sh,"
	@echo "or open it in Xcode and Run."

PHONY += ios-check-prereqs ios-info-plist xcodeproj FORCE

FORCE:
