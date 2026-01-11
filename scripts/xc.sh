#!/usr/bin/env bash
set -euo pipefail

# Source shared cleanup library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/cleanup.sh"

proj="Contextify/Contextify.xcodeproj"
scheme="Contextify"
# dd is set after argument parsing based on $dist

default_config="Debug"
default_action="build"

config="$default_config"
action="$default_action"
dev_mode=0
quiet_mode=1  # Quiet by default, use --verbose to see full output
fast_clean=0  # Fast clean mode (preserve dependencies like GRDB)
preserve_bookmarks=0  # Preserve security-scoped bookmarks during cleanrun

# Distribution mode (dmg vs appstore)
dist="dmg"
scheme_dmg="Contextify"
scheme_appstore="Contextify AppStore"  # Separate target without Sparkle
entitlements_dmg="Contextify.entitlements"
entitlements_appstore="Contextify-AppStore.entitlements"

# Fixtures
fixtures_root="$PWD/Fixtures/transcripts"
tmp_demo="${TMPDIR:-/tmp}/contextify-demo"

parse_arg() {
  local value="$1"
  case "$value" in
    --dev|--developer-mode)
      dev_mode=1
      ;;
    --verbose|-v)
      quiet_mode=0
      ;;
    --dist=appstore)
      dist="appstore"
      ;;
    --dist=dmg)
      dist="dmg"
      ;;
    Debug|Release)
      config="$value"
      ;;
    build|test|clean|cleanrun|reset-perms|reset-state|reset-all|logs|dev-archive|export-pkg|upload)
      action="$value"
      ;;
    ca)
      dist="appstore"
      action="cleanrun"
      ;;
    da)
      dist="dmg"
      action="cleanrun"
      ;;
    dr)
      # Fast cleanrun (like da, but preserves GRDB and dependencies)
      dist="dmg"
      action="cleanrun"
      fast_clean=1
      ;;
    ar)
      # Fast cleanrun for App Store (like dr, but sandboxed)
      dist="appstore"
      action="cleanrun"
      fast_clean=1
      ;;
    arp)
      # Fast cleanrun for App Store preserving bookmarks
      dist="appstore"
      action="cleanrun"
      fast_clean=1
      preserve_bookmarks=1
      ;;
    seed-demo)
      echo "ERROR: seed-demo is disabled - it interferes with active Claude Code usage" >&2
      echo "This command replaces ~/.claude/projects with test fixtures, causing active transcripts to be lost." >&2
      echo "Re-enable during final QA testing only." >&2
      exit 1
      ;;
    *)
      echo "usage: $0 [--dev] [--verbose] [--dist=dmg|appstore] [Debug|Release] [build|test|clean|cleanrun|reset-perms|reset-state|reset-all|logs|dev-archive|ca|da|dr|ar|arp]" >&2
      echo "" >&2
      echo "Options:" >&2
      echo "  --dev              Enable developer mode (shows test buttons)" >&2
      echo "  --verbose, -v      Show full build output (default: errors/warnings only)" >&2
      echo "  --dist=dmg         Build DMG distribution (unsandboxed, default)" >&2
      echo "  --dist=appstore    Build App Store distribution (sandboxed)" >&2
      echo "" >&2
      echo "Actions:" >&2
      echo "  build              Build and run (default)" >&2
      echo "  test               Run tests" >&2
      echo "  clean              Clean build artifacts" >&2
      echo "  cleanrun           Clean database + build + run (first-run)" >&2
      echo "  ca                 Shortcut for App Store cleanrun (db reset + perms + launch)" >&2
      echo "  da                 Shortcut for DMG cleanrun (full clean: db + perms + GRDB)" >&2
      echo "  dr                 Fast cleanrun (db + perms + app, preserves GRDB/deps)" >&2
      echo "  ar                 Fast App Store cleanrun (db + perms + app, preserves GRDB/deps)" >&2
      echo "  arp                Fast App Store cleanrun PRESERVING BOOKMARKS (for testing)" >&2
      echo "  dev-archive        Create dev/QA archive (scratch build, use release/build.sh for releases)" >&2
      echo "  export-pkg         Export archive as .pkg for App Store Connect" >&2
      echo "  upload             Upload .pkg to App Store Connect via altool" >&2
      echo "  reset-perms        Reset macOS privacy (TCC) permissions only" >&2
      echo "  reset-state        Reset app state (DB, prefs, bookmarks, CLI shim, plugin)" >&2
      echo "  reset-all          Reset both permissions and state" >&2
      echo "  logs               Stream app logs in real-time" >&2
      exit 2
      ;;
  esac
}

# Parse all arguments (supports --dev flag + config + action)
for arg in "$@"; do
  parse_arg "$arg"
done

# Set derived data path based on distribution (MUST be after argument parsing)
dd=".derived-${dist}"  # Results in .derived-dmg or .derived-appstore

# Print build configuration summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Contextify Build Configuration"
echo "═══════════════════════════════════════════════════════════════"
echo "  Distribution:  $dist $(if [[ "$dist" == "appstore" ]]; then echo "(sandboxed)"; else echo "(unsandboxed)"; fi)"
echo "  Configuration: $config"
echo "  Action:        $action"
if [[ "$dev_mode" -eq 1 ]]; then
  echo "  Developer Mode: ENABLED"
fi
echo ""
if [[ "$action" == "cleanrun" || "$action" == "ca" || "$action" == "da" || "$action" == "dr" || "$action" == "ar" || "$action" == "arp" ]]; then
  echo "  ⚠️  This will:"
  if [[ "$fast_clean" -eq 1 ]]; then
    echo "      • Clean app artifacts only (preserves GRDB/dependencies)"
  else
    echo "      • Clean build cache ($dd/)"
  fi
  echo "      • Wipe database (all projects/transcripts/entries)"
  if [[ "$preserve_bookmarks" -eq 1 ]]; then
    echo "      • Reset app preferences (PRESERVING security-scoped bookmarks)"
  else
    echo "      • Reset app preferences and bookmarks"
  fi
  echo "      • Reset TCC permissions (folder access, etc.)"
  echo "      • Remove CLI shim and plugin installations"
  echo "      • Launch fresh app instance"
elif [[ "$action" == "reset-state" ]]; then
  echo "  ⚠️  This will:"
  echo "      • Wipe database (all projects/transcripts/entries)"
  echo "      • Reset app preferences and bookmarks"
  echo "      • Remove CLI shim and plugin installations"
elif [[ "$action" == "reset-perms" ]]; then
  echo "  ⚠️  This will:"
  echo "      • Reset TCC permissions (folder access, etc.)"
elif [[ "$action" == "reset-all" ]]; then
  echo "  ⚠️  This will:"
  echo "      • Wipe database (all projects/transcripts/entries)"
  echo "      • Reset app preferences and bookmarks"
  echo "      • Reset TCC permissions (folder access, etc.)"
  echo "      • Remove CLI shim and plugin installations"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Detect non-macOS environments (Linux, WSL, etc.)
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo ""
  echo "⚠️  Contextify is a macOS project that requires Xcode to build."
  echo "   You are running on: $(uname -s)"
  echo ""
  echo "🚀 For Linux/Web-based Claude Code users:"
  echo "   Use the on-demand GitHub Actions workflow to build remotely on macOS runners."
  echo ""

  # Check if gh CLI is available
  if command -v gh >/dev/null 2>&1; then
    echo "📋 Detected GitHub CLI (gh). Options:"
    echo ""
    echo "   1. Auto-trigger CI build now:"
    echo "      gh workflow run on-demand-build.yml -f configuration=$config"
    echo ""
    echo "   2. Trigger and watch the build:"
    echo "      gh workflow run on-demand-build.yml -f configuration=$config && gh run watch"
    echo ""

    # Offer to auto-trigger
    if [[ -t 0 ]]; then  # Check if stdin is a terminal (interactive)
      read -p "   🤖 Trigger CI build now? [y/N] " -n 1 -r
      echo ""
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Triggering CI build with configuration: $config..."
        if gh workflow run on-demand-build.yml -f configuration="$config" -f skip_launch=true; then
          echo ""
          echo "   ✅ Workflow triggered successfully!"
          echo ""
          echo "   📊 View build status:"
          echo "      https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/workflows/on-demand-build.yml"
          echo ""
          echo "   📺 Watch build in real-time:"
          echo "      gh run watch"
          echo ""
          exit 0
        else
          echo ""
          echo "   ❌ Failed to trigger workflow. Check your GitHub authentication:"
          echo "      gh auth status"
          exit 1
        fi
      else
        echo "   Skipping auto-trigger."
      fi
    fi
  else
    echo "📋 GitHub CLI (gh) not found. Install it to auto-trigger CI builds:"
    echo "   https://cli.github.com/"
    echo ""
    echo "   Or manually trigger via GitHub web UI:"
  fi

  echo ""
  echo "🌐 Manual trigger options:"
  echo "   • Web UI: https://github.com/YOUR-REPO/actions/workflows/on-demand-build.yml"
  echo "   • gh CLI: gh workflow run on-demand-build.yml -f configuration=$config"
  echo ""
  echo "📖 For detailed documentation, see: AGENTS.md"
  echo ""
  exit 1
fi

# Check for build output formatters (prefer xcbeautify > xcpretty > raw)
have_xcbeautify=0
have_xcpretty=0
xcbeautify_renderer=""

if command -v xcbeautify >/dev/null 2>&1; then
  have_xcbeautify=1
  # Detect if running in GitHub Actions
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    xcbeautify_renderer="--renderer github-actions"
  fi
elif command -v xcpretty >/dev/null 2>&1; then
  have_xcpretty=1
fi

quit_running_app() {
  osascript -e 'tell application "Contextify" to quit' >/dev/null 2>&1 || true
  pkill -x Contextify >/dev/null 2>&1 || true
}

# Helper: Extract bundle ID from built app
bundle_id_for_app() {
  local app="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || echo "dev.contextify.Contextify"
}

# Helper: Find container base directory for a bundle ID
containers_base_for_bid() {
  local bid="$1"
  local cdir="$HOME/Library/Containers/$bid/Data/Library"
  if [[ -d "$cdir" ]]; then
    echo "$cdir"
  else
    echo "$HOME/Library"
  fi
}

# Helper: Get Application Support path for bundle ID
app_support_path_for_bid() {
  local bid="$1"
  local base
  base="$(containers_base_for_bid "$bid")"
  echo "$base/Application Support/Contextify"
}

# Helper: Get all possible preferences paths for bundle ID
prefs_paths_for_bid() {
  local bid="$1"
  echo "$HOME/Library/Preferences/$bid.plist"
  echo "$HOME/Library/Containers/$bid/Data/Library/Preferences/$bid.plist"
}

# Reset app state (DB, caches, preferences, bookmarks)
reset_state_for_bid() {
  local bid="$1"
  local preserve_bookmarks="${2:-false}"
  echo "Resetting app state for bundle ID: $bid"

  if [[ "$preserve_bookmarks" == "true" ]]; then
    echo "  (Preserving security-scoped bookmarks)"
  fi

  quit_running_app
  sleep 0.5

  # Remove Application Support (includes DB and optionally bookmarks)
  local as_path
  as_path="$(app_support_path_for_bid "$bid")"
  if [[ -d "$as_path" ]]; then
    if [[ "$preserve_bookmarks" == "true" ]]; then
      # Preserve bookmarks.plist, remove everything else
      local bookmarks_file="$as_path/bookmarks.plist"
      local temp_bookmarks="/tmp/contextify-bookmarks-backup-$$.plist"

      if [[ -f "$bookmarks_file" ]]; then
        echo "  Backing up bookmarks to: $temp_bookmarks"
        cp "$bookmarks_file" "$temp_bookmarks"
      fi

      echo "  Removing: $as_path (except bookmarks)"
      rm -rf "$as_path" 2>/dev/null || true

      if [[ -f "$temp_bookmarks" ]]; then
        mkdir -p "$as_path"
        echo "  Restoring bookmarks to: $bookmarks_file"
        mv "$temp_bookmarks" "$bookmarks_file"
      fi
    else
      echo "  Removing: $as_path"
      rm -rf "$as_path" 2>/dev/null || true
    fi
  fi

  # Remove caches and preferences using shared library (scripts/lib/cleanup.sh)
  echo "  Cleaning caches..."
  clean_caches_for_bid "$bid"
  echo "  Cleaning UserDefaults (bundle + $CONTEXTIFY_SUITE suite)..."
  clean_userdefaults_for_bid "$bid"

  # Clean CLI installations (shim + plugin)
  echo "  Cleaning CLI shim..."
  rm -f /opt/homebrew/bin/contextify-query 2>/dev/null || true
  rm -f /usr/local/bin/contextify-query 2>/dev/null || true
  rm -f "$HOME/bin/contextify-query" 2>/dev/null || true
  rm -f "$HOME/.local/bin/contextify-query" 2>/dev/null || true

  echo "  Cleaning Claude Code plugin..."
  rm -rf "$HOME/.claude/plugins/cache/contextify" 2>/dev/null || true

  # Update installed_plugins.json to remove our plugin entry
  local plugins_manifest="$HOME/.claude/plugins/installed_plugins.json"
  if [[ -f "$plugins_manifest" ]]; then
    # Use jq to remove query@contextify entry if available
    if command -v jq >/dev/null 2>&1; then
      local temp_manifest="/tmp/contextify-plugins-$$.json"
      jq 'del(.plugins["query@contextify"])' "$plugins_manifest" > "$temp_manifest" 2>/dev/null || true
      if [[ -s "$temp_manifest" ]]; then
        mv "$temp_manifest" "$plugins_manifest"
      else
        rm -f "$temp_manifest"
      fi
    else
      # Fallback: just remove the whole file if jq not available
      rm -f "$plugins_manifest" 2>/dev/null || true
    fi
  fi

  echo "App state reset complete"
}

# Reset TCC permissions for bundle ID
reset_tcc_for_bid() {
  local bid="$1"
  echo "Resetting TCC permissions for bundle ID: $bid"

  quit_running_app
  sleep 0.5

  # Reset all TCC permissions
  tccutil reset All "$bid" 2>/dev/null || true

  # Optionally reset specific services (uncomment for granular testing)
  # tccutil reset SystemPolicyDesktopFolder "$bid" 2>/dev/null || true
  # tccutil reset SystemPolicyDocumentsFolder "$bid" 2>/dev/null || true
  # tccutil reset SystemPolicyDownloadsFolder "$bid" 2>/dev/null || true
  # tccutil reset SystemPolicyNetworkVolumes "$bid" 2>/dev/null || true
  # tccutil reset SystemPolicyRemovableVolumes "$bid" 2>/dev/null || true

  echo "TCC permissions reset complete"
}

# Seed demo fixtures
seed_demo_fixtures() {
  echo "Seeding demo fixtures..."

  # Clean and create temp demo directory
  rm -rf "$tmp_demo"
  mkdir -p "$tmp_demo"

  # Copy fixtures if they exist (directly to tmp_demo, preserving structure)
  if [[ -d "$fixtures_root/claude" ]]; then
    echo "  Copying Claude fixtures..."
    mkdir -p "$tmp_demo/claude"
    rsync -a "$fixtures_root/claude/" "$tmp_demo/claude/"
  fi
  if [[ -d "$fixtures_root/codex" ]]; then
    echo "  Copying Codex fixtures..."
    mkdir -p "$tmp_demo/codex"
    rsync -a "$fixtures_root/codex/" "$tmp_demo/codex/"
  fi

  # Create home directories if they don't exist
  mkdir -p "$HOME/.claude" "$HOME/.codex"

  # Backup existing symlinks/directories
  if [[ -e "$HOME/.claude/projects" ]]; then
    local backup_name="projects.bak.$(date +%s)"
    echo "  Backing up existing ~/.claude/projects to $backup_name"
    mv "$HOME/.claude/projects" "$HOME/.claude/$backup_name" 2>/dev/null || true
  fi
  if [[ -e "$HOME/.codex/sessions" ]]; then
    local backup_name="sessions.bak.$(date +%s)"
    echo "  Backing up existing ~/.codex/sessions to $backup_name"
    mv "$HOME/.codex/sessions" "$HOME/.codex/$backup_name" 2>/dev/null || true
  fi

  # Create symlinks - note we symlink to projects/ and sessions/ subdirectories
  ln -sfn "$tmp_demo/claude/projects" "$HOME/.claude/projects"
  ln -sfn "$tmp_demo/codex/sessions" "$HOME/.codex/sessions"

  echo ""
  echo "Demo fixtures seeded successfully:"
  echo "  ~/.claude/projects -> $tmp_demo/claude/projects"
  echo "  ~/.codex/sessions  -> $tmp_demo/codex/sessions"
  echo ""

  # Show what was seeded
  local claude_count=$(find "$tmp_demo/claude/projects" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  local codex_count=$(find "$tmp_demo/codex/sessions" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  echo "Fixture summary:"
  echo "  Claude Code transcripts: $claude_count"
  echo "  Codex CLI transcripts: $codex_count"
  echo ""
  echo "Run './scripts/xc.sh cleanrun' to test first-run with this data"
}

# Stream app logs
watch_logs() {
  echo "Streaming Contextify logs (Ctrl-C to stop)..."
  echo ""
  log stream --style compact --predicate 'process == "Contextify"' --level debug
}

run_xcodebuild() {
  set -o pipefail

  # Build the pipeline: xcodebuild -> DVT filter -> formatter -> quiet filter (if enabled)
  local pipeline=""

  # Always filter out DVTAssertions warnings (Xcode internal noise)
  pipeline="sed '/DVTAssertions:/,/Please file a bug/d'"

  if [[ $have_xcbeautify -eq 1 ]]; then
    pipeline="$pipeline | xcbeautify $xcbeautify_renderer"
  elif [[ $have_xcpretty -eq 1 ]]; then
    pipeline="$pipeline | xcpretty"
  else
    pipeline="$pipeline | cat"
  fi

  # In quiet mode, filter to only show Swift compilation errors/warnings, build milestones, and build status
  # EXCEPT for tests - always show full output for tests
  if [[ $quiet_mode -eq 1 && "$action" != "test" ]]; then
    pipeline="$pipeline | grep -E '(\\.swift:[0-9]+:[0-9]+: (error|warning):|BUILD SUCCEEDED|BUILD FAILED|Built:|Launching|^\\([0-9]+ failures?\\)|Linking Contextify|Signing|CodeSign.*Contextify)' || true"
  fi

  echo "Running xcodebuild (this may take 1-2 minutes on first build)..."
  xcodebuild "$@" 2>&1 | eval "$pipeline"
}

# Build for the selected distribution
run_build_for_dist() {
  local selected_scheme
  if [[ "$dist" == "appstore" ]]; then
    selected_scheme="$scheme_appstore"
  else
    selected_scheme="$scheme_dmg"
  fi
  local cs_entitlements=""

  echo "Building for distribution: $dist"

  if [[ "$action" == "build" ]]; then
    # Plain build: incremental (no clean) for speed
    echo "  Incremental build (use 'clean' or 'cleanrun' for fresh build)..."
  elif [[ $fast_clean -eq 1 ]]; then
    echo "  Fast clean: removing Contextify app artifacts (preserving dependencies)..."
    rm -rf "$dd/Build/Intermediates.noindex/Contextify.build" 2>/dev/null || true
    rm -rf "$dd/Build/Products/$config/Contextify.app" 2>/dev/null || true
    rm -rf "$dd/Build/Products/$config/__preview.dylib" 2>/dev/null || true
  else
    echo "  Cleaning build cache to ensure fresh compilation..."
    rm -rf "$dd" 2>/dev/null || true
  fi

  if [[ "$dist" == "appstore" ]]; then
    echo "  Using App Store entitlements (sandboxed)"
    cs_entitlements="$entitlements_appstore"
  else
    echo "  Using DMG entitlements (unsandboxed) with Sparkle"
    cs_entitlements="$entitlements_dmg"
  fi

  # Note: INFOPLIST_FILE is set in the Xcode project per-configuration
  # (Debug uses Info-Debug.plist, Release uses Info.plist)
  # For Sparkle DMG builds, Info-DMG.plist should be configured via xcconfig
  # or by creating a separate scheme.

  if [[ -n "${CI:-}${GITHUB_ACTIONS:-}" ]]; then
    run_xcodebuild -project "$proj" -scheme "$selected_scheme" \
      -configuration "$config" -destination "platform=macOS,arch=arm64" \
      -derivedDataPath "$dd" \
      CODE_SIGN_IDENTITY="-" \
      DEVELOPMENT_TEAM="" \
      CODE_SIGN_ENTITLEMENTS="$cs_entitlements" \
      build
  else
    run_xcodebuild -project "$proj" -scheme "$selected_scheme" \
      -configuration "$config" -destination "platform=macOS,arch=arm64" \
      -derivedDataPath "$dd" \
      CODE_SIGN_ENTITLEMENTS="$cs_entitlements" \
      build
  fi

  app_path="$dd/Build/Products/$config/Contextify.app"
  echo "Built: $app_path"
}

# Handle new actions first (before the main case statement)
if [[ "$action" == "cleanrun" ]]; then
  echo "🧹 Cleaning database..."
  CONTEXTIFY_DIST="$dist" ./scripts/db_manager.sh clean --force

  echo "🔨 Building ($dist)..."
  quit_running_app
  run_build_for_dist

  bundle_id="$(bundle_id_for_app "$app_path")"
  echo "Bundle ID: $bundle_id"

  echo "♻️  Resetting app state and TCC..."
  if [[ "$preserve_bookmarks" == "1" ]]; then
    reset_state_for_bid "$bundle_id" "true"
  else
    reset_state_for_bid "$bundle_id" "false"
  fi
  reset_tcc_for_bid "$bundle_id"

  echo "🚀 Launching first-run..."
  open "$app_path"
  exit 0
fi

# Individual reset actions
if [[ "$action" == "reset-perms" || "$action" == "reset-state" || "$action" == "reset-all" ]]; then
  # Build to get the bundle ID
  quit_running_app
  run_build_for_dist

  bundle_id="$(bundle_id_for_app "$app_path")"
  echo "Bundle ID: $bundle_id"

  if [[ "$action" == "reset-perms" || "$action" == "reset-all" ]]; then
    reset_tcc_for_bid "$bundle_id"
  fi

  if [[ "$action" == "reset-state" || "$action" == "reset-all" ]]; then
    reset_state_for_bid "$bundle_id"
  fi

  echo ""
  echo "Reset complete. Run './scripts/xc.sh build' to launch the app."
  exit 0
fi

# Seed demo fixtures
if [[ "$action" == "seed-demo" ]]; then
  seed_demo_fixtures
  exit 0
fi

# Stream logs
if [[ "$action" == "logs" ]]; then
  watch_logs
  exit 0
fi

# Archive for App Store
# Scratch location for dev/QA builds (overwritten frequently)
# For official release builds, use: scripts/release/build.sh X.Y.Z
#   which archives to: build/archives/v{VERSION}/appstore/
archive_path="build/Contextify.xcarchive"
pkg_path="build/appstore/Contextify.pkg"
export_options_plist="ExportOptions-AppStore.plist"

if [[ "$action" == "dev-archive" ]]; then
  echo "📦 Creating Xcode archive (dev/QA scratch build)..."
  echo "   Location: $archive_path"
  echo ""
  echo "   Note: For official release builds, use: scripts/release/build.sh X.Y.Z"
  quit_running_app

  # Always use Release for archives
  config="Release"

  # Select scheme based on distribution
  if [[ "$dist" == "appstore" ]]; then
    archive_scheme="$scheme_appstore"
  else
    archive_scheme="$scheme_dmg"
  fi

  # Clean previous archive
  rm -rf "$archive_path"
  mkdir -p build

  run_xcodebuild -project "$proj" -scheme "$archive_scheme" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$dd" \
    -archivePath "$archive_path" \
    archive

  echo ""
  echo "✅ Archive created: $archive_path"
  echo ""
  echo "Next steps:"
  echo "  - For dev/QA: open $archive_path/Products/Applications/Contextify.app"
  echo "  - For release: scripts/release/build.sh X.Y.Z (archives to build/archives/)"
  exit 0
fi

if [[ "$action" == "export-pkg" ]]; then
  if [[ "$dist" != "appstore" ]]; then
    echo "⚠️  Warning: export-pkg is for App Store builds."
    echo "   You may want to use: bash scripts/xc.sh --dist=appstore dev-archive"
    echo ""
  fi
  echo "📦 Exporting archive as .pkg for App Store Connect..."

  if [[ ! -d "$archive_path" ]]; then
    echo "❌ Archive not found at: $archive_path"
    echo "   Run 'bash scripts/xc.sh dev-archive' first"
    exit 1
  fi

  if [[ ! -f "$export_options_plist" ]]; then
    echo "❌ Export options plist not found at: $export_options_plist"
    exit 1
  fi

  # Clean previous export
  rm -rf build/appstore
  mkdir -p build/appstore

  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath build/appstore \
    -exportOptionsPlist "$export_options_plist"

  # Find the exported pkg
  exported_pkg=$(find build/appstore -name "*.pkg" -type f 2>/dev/null | head -1)

  if [[ -n "$exported_pkg" ]]; then
    echo ""
    echo "✅ Package created: $exported_pkg"
    echo ""
    echo "Next step: Run 'bash scripts/xc.sh upload' to upload to App Store Connect"
  else
    echo ""
    echo "⚠️  Export completed but no .pkg found. Check build/appstore/ for output."
  fi
  exit 0
fi

if [[ "$action" == "upload" ]]; then
  if [[ "$dist" != "appstore" ]]; then
    echo "⚠️  Warning: upload is for App Store builds."
    echo "   You may want to use: bash scripts/xc.sh --dist=appstore dev-archive"
    echo ""
  fi
  echo "🚀 Uploading to App Store Connect..."

  # Find the pkg
  exported_pkg=$(find build/appstore -name "*.pkg" -type f 2>/dev/null | head -1)

  if [[ -z "$exported_pkg" ]]; then
    echo "❌ No .pkg found in build/appstore/"
    echo "   Run 'bash scripts/xc.sh dev-archive' then 'bash scripts/xc.sh export-pkg' first"
    exit 1
  fi

  # Check for API credentials
  api_key_id="AG868N57U6"
  api_issuer_id="69a6de89-2083-47e3-e053-5b8c7c11a4d1"
  api_key_path=".secrets/AuthKey_${api_key_id}.p8"

  if [[ ! -f "$api_key_path" ]]; then
    echo "❌ API key not found at: $api_key_path"
    echo "   Download from App Store Connect and place in .secrets/"
    exit 1
  fi

  echo "Uploading: $exported_pkg"
  echo "Using API Key: $api_key_id"
  echo ""

  xcrun altool --upload-app \
    --type macos \
    --file "$exported_pkg" \
    --apiKey "$api_key_id" \
    --apiIssuer "$api_issuer_id"

  echo ""
  echo "✅ Upload complete! Check App Store Connect for build status."
  exit 0
fi

case "$action" in
  clean)
    rm -rf "$dd"
    ;;
  build)
    quit_running_app
    run_build_for_dist

    if [[ -z "${CTX_NO_RUN:-}" ]]; then
      # Set developer mode if --dev flag was provided
      if [[ $dev_mode -eq 1 ]]; then
        echo "Enabling developer mode..."
        defaults write dev.contextify.Contextify DeveloperModeEnabled -bool true
      else
        # Ensure developer mode is disabled by default
        defaults write dev.contextify.Contextify DeveloperModeEnabled -bool false
      fi
      echo "Launching $app_path"
      open "$app_path"
    fi
    ;;
  test)
    quit_running_app

    # For tests, use the standard scheme (not distribution-specific)
    if [[ -n "${CI:-}${GITHUB_ACTIONS:-}" ]]; then
      run_xcodebuild -project "$proj" -scheme "$scheme" \
        -configuration "$config" -destination "platform=macOS,arch=arm64" \
        -derivedDataPath "$dd" \
        CODE_SIGN_IDENTITY="-" \
        DEVELOPMENT_TEAM="" \
        test
    else
      run_xcodebuild -project "$proj" -scheme "$scheme" \
        -configuration "$config" -destination "platform=macOS,arch=arm64" \
        -derivedDataPath "$dd" test
    fi
    ;;
  *)
    echo "usage: $0 [--dev] [--verbose] [--dist=dmg|appstore] [Debug|Release] [build|test|clean|cleanrun|reset-perms|reset-state|reset-all|dev-archive|logs|ca]" >&2
    echo "Run '$0' without arguments for full help" >&2
    exit 2
    ;;
esac
