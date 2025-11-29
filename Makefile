# Minimal helpers that delegate to scripts/xc.sh to avoid duplication.

.PHONY: build build-release test clean hooks-setup setup logs logs-live clean-db debug db-backup db-restore db-list sign-dmg sign-dmg-no-notarize release release-dry-run

build:
	bash scripts/xc.sh build

build-release:
	bash scripts/xc.sh Release build

test:
	bash scripts/xc.sh test

clean:
	rm -rf build/DerivedData build/DerivedData-beta

hooks-setup:
	@chmod +x .githooks/pre-commit || true
	@chmod +x scripts/xc.sh || true
	@git config core.hooksPath .githooks
	@echo "Git hooks enabled (core.hooksPath=.githooks). Pre-commit build guard active."

setup: hooks-setup build
	@echo "Setup complete. See build/logs/ for build output."

# Log capture targets
logs:
	@bash scripts/capture-recent-logs.sh 5

logs-live:
	@bash scripts/stream-logs.sh /tmp/contextify-live.log

# Database management (ALWAYS creates backup before cleaning)
# ⚠️  WARNING: Use db_manager.sh for ALL database operations
# ⚠️  NEVER delete database files manually or with rm
clean-db:
	@echo "⚠️  Using safe database cleanup (creates automatic backup)..."
	@bash scripts/db_manager.sh clean

db-backup:
	@bash scripts/db_manager.sh backup

db-restore:
	@bash scripts/db_manager.sh restore latest

db-list:
	@bash scripts/db_manager.sh list

# Build with automatic log capture (30 seconds)
debug:
	@bash scripts/build-and-capture-logs.sh 30

# Release workflow targets
# Sign and create DMG with notarization (production)
sign-dmg:
	@python3 scripts/sign_and_notarize.py

# Sign and create DMG without notarization (faster testing)
sign-dmg-no-notarize:
	@python3 scripts/sign_and_notarize.py --no-notarize

# Full release workflow (interactive)
release:
	@python3 scripts/release.py

# Dry-run release (preview what would happen)
release-dry-run:
	@python3 scripts/release.py --dry-run

# App Store submission workflow (dev-archive for scratch builds)
dev-archive:
	@bash scripts/xc.sh dev-archive

export-pkg:
	@bash scripts/xc.sh export-pkg

upload:
	@bash scripts/xc.sh upload

# Full App Store submission (dev-archive + export + upload)
appstore-submit: dev-archive export-pkg upload
