#!/usr/bin/env bash
#
# validate-live-systems.sh - Validate all Contextify live systems
#
# Performs curl-based checks against all live endpoints and artifacts:
#   Section A: Cloud Health & Security (7 checks)
#   Section B: Sparkle Feed Integrity (8 checks)
#   Section C: Linux Artifact SHA Integrity (6 checks)
#   Section D: Cross-Surface Consistency (4 checks)
#
# Usage:
#   ./scripts/validate-live-systems.sh [OPTIONS]
#
# Options:
#   --json          Output results as JSON to stdout
#   --quiet         Suppress passing checks (human mode only)
#   --section NAME  Run only named section (cloud, sparkle, linux, consistency)
#                   Can be specified multiple times
#   --no-color      Disable ANSI color codes (auto-detected for non-TTY)
#   --help          Show this help
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed
#   2 - Script error (missing dependency, invalid arguments)
#
# Environment variables:
#   CLOUD_BASE_URL       (default: https://cloud.contextify.sh)
#   WEBSITE_BASE_URL     (default: https://contextify.sh)
#   GITHUB_RELEASE_REPO  (default: PeterPym/contextify)

set -eo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

CLOUD_BASE_URL="${CLOUD_BASE_URL:-https://cloud.contextify.sh}"
WEBSITE_BASE_URL="${WEBSITE_BASE_URL:-https://contextify.sh}"
GITHUB_RELEASE_REPO="${GITHUB_RELEASE_REPO:-PeterPym/contextify}"

CURL_OPTS=(--silent --show-error --connect-timeout 5 --max-time 15)
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── Colors ─────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Auto-detect non-TTY
if [ ! -t 1 ]; then
  NO_COLOR=true
fi

# ── Options ────────────────────────────────────────────────────────────────────

JSON_MODE=false
QUIET=false
NO_COLOR="${NO_COLOR:-false}"
declare -a SECTIONS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --json) JSON_MODE=true; shift ;;
    --quiet) QUIET=true; shift ;;
    --no-color) NO_COLOR=true; shift ;;
    --section)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --section requires a value" >&2
        exit 2
      fi
      case "$2" in
        cloud|sparkle|linux|consistency) SECTIONS+=("$2") ;;
        *) echo "Error: unknown section '$2' (valid: cloud, sparkle, linux, consistency)" >&2; exit 2 ;;
      esac
      shift 2
      ;;
    --help|-h)
      sed -n '2,31p' "$0" | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

# Disable colors if requested
if [ "$NO_COLOR" = true ]; then
  RED='' GREEN='' YELLOW='' BOLD='' NC=''
fi

# Default: run all sections
if [ ${#SECTIONS[@]} -eq 0 ]; then
  SECTIONS=(cloud sparkle linux consistency)
fi

# ── Helpers ────────────────────────────────────────────────────────────────────

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# JSON check accumulators (temp files)
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

: > "$TMP_DIR/cloud.json"
: > "$TMP_DIR/sparkle.json"
: > "$TMP_DIR/linux.json"
: > "$TMP_DIR/consistency.json"

CLOUD_PASS=0; CLOUD_FAIL=0; CLOUD_SKIP=0
SPARKLE_PASS=0; SPARKLE_FAIL=0; SPARKLE_SKIP=0
LINUX_PASS=0; LINUX_FAIL=0; LINUX_SKIP=0
CONSISTENCY_PASS=0; CONSISTENCY_FAIL=0; CONSISTENCY_SKIP=0

# Version snapshot
VER_MACOS="" VER_CLI="" VER_SPARKLE="" VER_SPARKLE_BUILD=""

# Append a JSON check object to the section accumulator file
# Usage: json_add <section> <id> <name> <status> <detail>
json_add() {
  local section="$1" id="$2" name="$3" status="$4" detail="$5"
  # Use python3 or printf to safely produce JSON
  local json_line
  if command -v python3 &>/dev/null; then
    json_line=$(python3 -c "
import json, sys
print(json.dumps({'id': sys.argv[1], 'name': sys.argv[2], 'status': sys.argv[3], 'detail': sys.argv[4]}))
" "$id" "$name" "$status" "$detail" 2>/dev/null)
  else
    # Manual escape for JSON safety
    detail="${detail//\\/\\\\}"
    detail="${detail//\"/\\\"}"
    name="${name//\\/\\\\}"
    name="${name//\"/\\\"}"
    json_line="{\"id\":\"${id}\",\"name\":\"${name}\",\"status\":\"${status}\",\"detail\":\"${detail}\"}"
  fi
  echo "$json_line" >> "$TMP_DIR/${section}.json"
}

# Record a passing check
# Usage: pass <section> <id> <name> <detail>
pass() {
  local section="$1" id="$2" name="$3" detail="$4"
  case "$section" in
    cloud) CLOUD_PASS=$((CLOUD_PASS + 1)) ;;
    sparkle) SPARKLE_PASS=$((SPARKLE_PASS + 1)) ;;
    linux) LINUX_PASS=$((LINUX_PASS + 1)) ;;
    consistency) CONSISTENCY_PASS=$((CONSISTENCY_PASS + 1)) ;;
  esac
  TOTAL_PASS=$((TOTAL_PASS + 1))
  json_add "$section" "$id" "$name" "pass" "$detail"
  if [ "$JSON_MODE" = false ] && [ "$QUIET" = false ]; then
    printf "  ${GREEN}PASS${NC}  %-4s %s\n" "$id" "$detail"
  fi
}

# Record a failing check
# Usage: fail <section> <id> <name> <detail>
fail() {
  local section="$1" id="$2" name="$3" detail="$4"
  case "$section" in
    cloud) CLOUD_FAIL=$((CLOUD_FAIL + 1)) ;;
    sparkle) SPARKLE_FAIL=$((SPARKLE_FAIL + 1)) ;;
    linux) LINUX_FAIL=$((LINUX_FAIL + 1)) ;;
    consistency) CONSISTENCY_FAIL=$((CONSISTENCY_FAIL + 1)) ;;
  esac
  TOTAL_FAIL=$((TOTAL_FAIL + 1))
  json_add "$section" "$id" "$name" "fail" "$detail"
  if [ "$JSON_MODE" = false ]; then
    printf "  ${RED}FAIL${NC}  %-4s %s\n" "$id" "$detail"
  fi
}

# Record a skipped check
# Usage: skip <section> <id> <name> <detail>
skip() {
  local section="$1" id="$2" name="$3" detail="$4"
  case "$section" in
    cloud) CLOUD_SKIP=$((CLOUD_SKIP + 1)) ;;
    sparkle) SPARKLE_SKIP=$((SPARKLE_SKIP + 1)) ;;
    linux) LINUX_SKIP=$((LINUX_SKIP + 1)) ;;
    consistency) CONSISTENCY_SKIP=$((CONSISTENCY_SKIP + 1)) ;;
  esac
  TOTAL_SKIP=$((TOTAL_SKIP + 1))
  json_add "$section" "$id" "$name" "skip" "$detail"
  if [ "$JSON_MODE" = false ] && [ "$QUIET" = false ]; then
    printf "  ${YELLOW}SKIP${NC}  %-4s %s\n" "$id" "$detail"
  fi
}

# Curl helper: return HTTP status code
# Note: curl -w '%{http_code}' writes "000" on connection failure, so we
# capture it in a variable to avoid appending a second "000" from the fallback.
curl_code() {
  local code
  code=$(curl "${CURL_OPTS[@]}" -o /dev/null -w '%{http_code}' "$@" 2>/dev/null) || true
  echo "${code:-000}"
}

# Curl helper: return headers
curl_headers() {
  curl "${CURL_OPTS[@]}" -D - -o /dev/null "$@" 2>/dev/null || true
}

section_header() {
  if [ "$JSON_MODE" = false ]; then
    echo ""
    printf "${BOLD}[%s] %s${NC}\n" "$1" "$2"
  fi
}

# Build JSON array from temp file lines (one JSON object per line)
build_json_array() {
  local file="$1"
  if [ ! -s "$file" ]; then
    echo "[]"
    return
  fi
  local result="["
  local first=true
  while IFS= read -r line; do
    if [ "$first" = true ]; then
      first=false
    else
      result="${result},"
    fi
    result="${result}${line}"
  done < "$file"
  result="${result}]"
  echo "$result"
}

# ── Section A: Cloud Health & Security ─────────────────────────────────────────

run_cloud_checks() {
  section_header "A" "Cloud Health & Security"

  # A1: Health endpoint
  local health_body health_code
  local tmp_health
  tmp_health="$(mktemp)"
  health_code=$(curl "${CURL_OPTS[@]}" -o "$tmp_health" -w '%{http_code}' "$CLOUD_BASE_URL/api/v1/health" 2>/dev/null) || true
  health_body="$(cat "$tmp_health" 2>/dev/null || true)"
  rm -f "$tmp_health"

  if [ "$health_code" = "200" ]; then
    if echo "$health_body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'; then
      pass cloud A1 "Health endpoint" "Health endpoint returns 200 with status ok"
    else
      fail cloud A1 "Health endpoint" "Cloud health status is not ok"
    fi
  else
    fail cloud A1 "Health endpoint" "Cloud health endpoint returned $health_code (expected 200)"
  fi

  # A2: Auth redirect
  local redirect_code
  redirect_code=$(curl_code --max-redirs 0 "$CLOUD_BASE_URL/cloud/")
  if [ "$redirect_code" = "303" ]; then
    pass cloud A2 "Auth redirect" "Auth redirect returns 303"
  else
    fail cloud A2 "Auth redirect" "Cloud auth redirect returned $redirect_code (expected 303)"
  fi

  # Shared curl for A3-A6: fetch /cloud/login with headers
  local login_code login_headers
  local tmp_login_headers
  tmp_login_headers="$(mktemp)"
  login_code=$(curl "${CURL_OPTS[@]}" -D "$tmp_login_headers" -o /dev/null -w '%{http_code}' "$CLOUD_BASE_URL/cloud/login" 2>/dev/null) || true
  login_headers="$(cat "$tmp_login_headers" 2>/dev/null || true)"
  rm -f "$tmp_login_headers"

  # A3: Login page
  if [ "$login_code" = "200" ]; then
    pass cloud A3 "Login page" "Login page returns 200"
  else
    fail cloud A3 "Login page" "Cloud login page returned $login_code (expected 200)"
  fi

  # A4: Content-Security-Policy
  local csp_value
  csp_value=$(echo "$login_headers" | grep -i '^Content-Security-Policy:' | head -1 | sed 's/^[^:]*: *//' | tr -d '\r' || true)
  if [ -n "$csp_value" ]; then
    if echo "$csp_value" | grep -qi 'frame-ancestors'; then
      pass cloud A4 "CSP header" "Content-Security-Policy header present"
    else
      fail cloud A4 "CSP header" "Content-Security-Policy header missing frame-ancestors"
    fi
  else
    fail cloud A4 "CSP header" "Content-Security-Policy header missing on /cloud/login"
  fi

  # A5: Security headers
  local all_sec_headers_present=true
  local missing_headers=""
  for hdr in "X-Frame-Options" "X-Content-Type-Options" "Referrer-Policy" "Permissions-Policy"; do
    if ! echo "$login_headers" | grep -qi "^${hdr}:"; then
      all_sec_headers_present=false
      missing_headers="${missing_headers}${hdr}, "
    fi
  done
  if [ "$all_sec_headers_present" = true ]; then
    pass cloud A5 "Security headers" "Security headers present (X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy)"
  else
    missing_headers="${missing_headers%, }"
    fail cloud A5 "Security headers" "${missing_headers} header(s) missing on /cloud/login"
  fi

  # A6: HSTS
  local hsts_value max_age
  hsts_value=$(echo "$login_headers" | grep -i '^Strict-Transport-Security:' | head -1 | sed 's/^[^:]*: *//' | tr -d '\r' || true)
  if [ -n "$hsts_value" ]; then
    max_age=$(echo "$hsts_value" | grep -o 'max-age=[0-9]*' | cut -d= -f2)
    if [ -n "$max_age" ] && [ "$max_age" -ge 86400 ]; then
      pass cloud A6 "HSTS" "HSTS max-age=$max_age"
    else
      fail cloud A6 "HSTS" "HSTS max-age too low: ${max_age:-missing}"
    fi
  else
    fail cloud A6 "HSTS" "HSTS header missing on /cloud/login"
  fi

  # A7: Static assets
  local css_code css_body
  local tmp_css
  tmp_css="$(mktemp)"
  css_code=$(curl "${CURL_OPTS[@]}" -o "$tmp_css" -w '%{http_code}' "$CLOUD_BASE_URL/cloud/static/dashboard.css" 2>/dev/null) || true
  css_body="$(cat "$tmp_css" 2>/dev/null || true)"
  rm -f "$tmp_css"

  if [ "$css_code" = "200" ] && [ -n "$css_body" ]; then
    pass cloud A7 "Static assets" "Static asset dashboard.css served"
  else
    fail cloud A7 "Static assets" "Static asset dashboard.css not served (HTTP $css_code)"
  fi
}

# ── Section B: Sparkle Feed Integrity ──────────────────────────────────────────

run_sparkle_checks() {
  section_header "B" "Sparkle Feed Integrity"

  # B1: Feed reachable
  local appcast_body appcast_code
  local tmp_appcast
  tmp_appcast="$(mktemp)"
  appcast_code=$(curl "${CURL_OPTS[@]}" -o "$tmp_appcast" -w '%{http_code}' "$WEBSITE_BASE_URL/appcast.xml" 2>/dev/null) || true
  appcast_body="$(cat "$tmp_appcast" 2>/dev/null || true)"
  rm -f "$tmp_appcast"

  if [ "$appcast_code" = "200" ] && [ -n "$appcast_body" ]; then
    pass sparkle B1 "Feed reachable" "Feed reachable (HTTP 200)"
  else
    fail sparkle B1 "Feed reachable" "Sparkle feed unreachable or empty (HTTP $appcast_code)"
    # Skip dependent checks
    skip sparkle B2 "Valid XML" "Skipped: prerequisite B1 failed"
    skip sparkle B3 "Latest version" "Skipped: prerequisite B1 failed"
    skip sparkle B4 "Latest build number" "Skipped: prerequisite B1 failed"
    skip sparkle B5 "EdDSA signature" "Skipped: prerequisite B1 failed"
    skip sparkle B6 "Enclosure length" "Skipped: prerequisite B1 failed"
    skip sparkle B7 "Enclosure URL" "Skipped: prerequisite B1 failed"
    skip sparkle B8 "minimumSystemVersion" "Skipped: prerequisite B1 failed"
    return
  fi

  # Check if python3 is available
  local use_python=true
  if ! command -v python3 &>/dev/null; then
    use_python=false
    if [ "$JSON_MODE" = false ] && [ "$QUIET" = false ]; then
      printf "  ${YELLOW}WARN${NC}  python3 not found; Sparkle checks using fallback parsing\n"
    fi
  fi

  local sparkle_version="" sparkle_build="" sparkle_signature="" sparkle_length=""
  local sparkle_url="" sparkle_min_sys="" xml_valid=""

  if [ "$use_python" = true ]; then
    # Single python3 invocation to parse appcast and return JSON
    local parse_result
    parse_result=$(python3 -c "
import xml.etree.ElementTree as ET
import json, sys

xml_data = sys.stdin.read()
result = {
    'xml_valid': False,
    'version': '',
    'build': '',
    'signature': '',
    'length': '',
    'url': '',
    'min_sys': ''
}

try:
    root = ET.fromstring(xml_data)
    result['xml_valid'] = True
except ET.ParseError:
    print(json.dumps(result))
    sys.exit(0)

ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}

# Find first item (latest)
items = root.findall('.//item')
if not items:
    print(json.dumps(result))
    sys.exit(0)

item = items[0]

# shortVersionString - could be element or enclosure attribute
ver_el = item.find('sparkle:shortVersionString', ns)
if ver_el is not None and ver_el.text:
    result['version'] = ver_el.text.strip()

# build number - could be element or enclosure attribute
build_el = item.find('sparkle:version', ns)
if build_el is not None and build_el.text:
    result['build'] = build_el.text.strip()

# Enclosure attributes
enc = item.find('enclosure')
if enc is not None:
    result['url'] = enc.get('url', '')
    result['length'] = enc.get('length', '')
    result['signature'] = enc.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature', '')
    # Also check shortVersionString/version on enclosure if not found as elements
    if not result['version']:
        result['version'] = enc.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString', '')
    if not result['build']:
        result['build'] = enc.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}version', '')

# minimumSystemVersion
min_sys = item.find('sparkle:minimumSystemVersion', ns)
if min_sys is not None and min_sys.text:
    result['min_sys'] = min_sys.text.strip()

print(json.dumps(result))
" <<< "$appcast_body" 2>/dev/null || echo '{"xml_valid":false}')

    xml_valid=$(echo "$parse_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('xml_valid',''))" 2>/dev/null || echo "")
    sparkle_version=$(echo "$parse_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || echo "")
    sparkle_build=$(echo "$parse_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('build',''))" 2>/dev/null || echo "")
    sparkle_signature=$(echo "$parse_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('signature',''))" 2>/dev/null || echo "")
    sparkle_length=$(echo "$parse_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('length',''))" 2>/dev/null || echo "")
    sparkle_url=$(echo "$parse_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || echo "")
    sparkle_min_sys=$(echo "$parse_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('min_sys',''))" 2>/dev/null || echo "")
  else
    # Fallback: grep/sed parsing
    xml_valid="fallback"
    sparkle_version=$(echo "$appcast_body" | grep -o 'sparkle:shortVersionString="[^"]*"' | head -1 | sed 's/.*="//' | sed 's/"//')
    if [ -z "$sparkle_version" ]; then
      sparkle_version=$(echo "$appcast_body" | grep -o '<sparkle:shortVersionString>[^<]*' | head -1 | sed 's/<[^>]*>//')
    fi
    sparkle_build=$(echo "$appcast_body" | grep -o 'sparkle:version="[^"]*"' | head -1 | sed 's/.*="//' | sed 's/"//')
    if [ -z "$sparkle_build" ]; then
      sparkle_build=$(echo "$appcast_body" | grep -o '<sparkle:version>[^<]*' | head -1 | sed 's/<[^>]*>//')
    fi
    sparkle_signature=$(echo "$appcast_body" | grep -o 'sparkle:edSignature="[^"]*"' | head -1 | sed 's/.*="//' | sed 's/"//')
    sparkle_length=$(echo "$appcast_body" | grep -o 'length="[^"]*"' | head -1 | sed 's/.*="//' | sed 's/"//')
    sparkle_url=$(echo "$appcast_body" | grep -o 'url="[^"]*"' | head -1 | sed 's/.*="//' | sed 's/"//')
    sparkle_min_sys=$(echo "$appcast_body" | grep -o '<sparkle:minimumSystemVersion>[^<]*' | head -1 | sed 's/<[^>]*>//')
  fi

  # Store for cross-section use
  VER_SPARKLE="$sparkle_version"
  VER_SPARKLE_BUILD="$sparkle_build"
  # Export for Section D
  SPARKLE_URL_FOR_D="$sparkle_url"

  # B2: Valid XML
  if [ "$use_python" = true ]; then
    if [ "$xml_valid" = "True" ]; then
      pass sparkle B2 "Valid XML" "Valid XML"
    else
      fail sparkle B2 "Valid XML" "Sparkle feed is not valid XML"
    fi
  else
    skip sparkle B2 "Valid XML" "Skipped: python3 not available for XML validation"
  fi

  # B3: Latest version present
  if [ -n "$sparkle_version" ]; then
    pass sparkle B3 "Latest version" "Latest version: $sparkle_version"
  else
    fail sparkle B3 "Latest version" "Sparkle feed has no version in latest item"
  fi

  # B4: Latest build number
  if [ -n "$sparkle_build" ]; then
    pass sparkle B4 "Latest build number" "Latest build number: $sparkle_build"
  else
    fail sparkle B4 "Latest build number" "Sparkle feed has no build number in latest item"
  fi

  # B5: EdDSA signature
  if [ -n "$sparkle_signature" ] && [ "$sparkle_signature" != "SIGNATURE_PLACEHOLDER" ]; then
    pass sparkle B5 "EdDSA signature" "EdDSA signature present (non-placeholder)"
  else
    fail sparkle B5 "EdDSA signature" "Sparkle EdDSA signature is missing or placeholder"
  fi

  # B6: Enclosure length
  if [ -n "$sparkle_length" ] && [ "$sparkle_length" != "0" ] && [[ "$sparkle_length" =~ ^[0-9]+$ ]]; then
    pass sparkle B6 "Enclosure length" "Enclosure length: $sparkle_length"
  else
    fail sparkle B6 "Enclosure length" "Sparkle enclosure length is 0 or missing"
  fi

  # B7: Enclosure URL resolves
  if [ -n "$sparkle_url" ]; then
    local enc_code
    enc_code=$(curl_code -L --max-redirs 5 -I "$sparkle_url")
    if [ "$enc_code" = "200" ] || [ "$enc_code" = "302" ]; then
      pass sparkle B7 "Enclosure URL" "Enclosure URL resolves (HTTP $enc_code)"
    else
      fail sparkle B7 "Enclosure URL" "Sparkle enclosure URL does not resolve: $sparkle_url (HTTP $enc_code)"
    fi
  else
    fail sparkle B7 "Enclosure URL" "Sparkle enclosure URL is empty"
  fi

  # B8: minimumSystemVersion
  if [ -n "$sparkle_min_sys" ]; then
    pass sparkle B8 "minimumSystemVersion" "minimumSystemVersion: $sparkle_min_sys"
  else
    fail sparkle B8 "minimumSystemVersion" "Sparkle minimumSystemVersion missing from latest item"
  fi
}

# ── Section C: Linux Artifact SHA Integrity ────────────────────────────────────

run_linux_checks() {
  section_header "C" "Linux Artifact SHA Integrity"

  # C1: cli-version.txt reachable and valid semver
  local cli_version cli_code
  local tmp_cli
  tmp_cli="$(mktemp)"
  cli_code=$(curl "${CURL_OPTS[@]}" -o "$tmp_cli" -w '%{http_code}' "$WEBSITE_BASE_URL/cli-version.txt" 2>/dev/null) || true
  cli_version="$(tr -d '\r\n' < "$tmp_cli" 2>/dev/null || true)"
  rm -f "$tmp_cli"

  if [ "$cli_code" = "200" ] && [[ "$cli_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    VER_CLI="$cli_version"
    pass linux C1 "cli-version.txt" "cli-version.txt: $cli_version"
  else
    fail linux C1 "cli-version.txt" "cli-version.txt unreachable or invalid semver (HTTP $cli_code, value: ${cli_version:-empty})"
    skip linux C2 "x86_64 tarball" "Skipped: prerequisite C1 failed"
    skip linux C3 "x86_64 SHA256 sidecar" "Skipped: prerequisite C1 failed"
    skip linux C4 "arm64 tarball" "Skipped: prerequisite C1 failed"
    skip linux C5 "arm64 SHA256 sidecar" "Skipped: prerequisite C1 failed"
    skip linux C6 "SHA sidecar filenames" "Skipped: prerequisite C1 failed"
    return
  fi

  local github_dl_base="https://github.com/${GITHUB_RELEASE_REPO}/releases/download/v${cli_version}"

  # C2: x86_64 tarball exists
  local x86_tarball="contextify-linux-x86_64.tar.gz"
  local x86_code
  x86_code=$(curl_code -I "$github_dl_base/$x86_tarball")
  if [ "$x86_code" = "302" ] || [ "$x86_code" = "200" ]; then
    pass linux C2 "x86_64 tarball" "x86_64 tarball exists (HTTP $x86_code)"
  else
    fail linux C2 "x86_64 tarball" "Linux x86_64 tarball not found for v${cli_version} (HTTP $x86_code)"
  fi

  # C3: x86_64 SHA256 sidecar valid
  local x86_sha_content="" x86_sha_code x86_sha_valid=false
  local tmp_x86_sha
  tmp_x86_sha="$(mktemp)"
  x86_sha_code=$(curl "${CURL_OPTS[@]}" -L -o "$tmp_x86_sha" -w '%{http_code}' "$github_dl_base/${x86_tarball}.sha256" 2>/dev/null) || true
  x86_sha_content="$(cat "$tmp_x86_sha" 2>/dev/null || true)"
  rm -f "$tmp_x86_sha"

  local x86_sha_hash
  x86_sha_hash=$(echo "$x86_sha_content" | head -1 | awk '{print $1}')
  if [ "$x86_sha_code" = "200" ] && [[ "$x86_sha_hash" =~ ^[0-9a-f]{64}$ ]]; then
    x86_sha_valid=true
    pass linux C3 "x86_64 SHA256 sidecar" "x86_64 SHA256 sidecar valid"
  else
    fail linux C3 "x86_64 SHA256 sidecar" "Linux x86_64 SHA256 sidecar missing or invalid format (HTTP $x86_sha_code)"
  fi

  # C4: arm64 tarball exists
  local arm64_tarball="contextify-linux-arm64.tar.gz"
  local arm64_code
  arm64_code=$(curl_code -I "$github_dl_base/$arm64_tarball")
  if [ "$arm64_code" = "302" ] || [ "$arm64_code" = "200" ]; then
    pass linux C4 "arm64 tarball" "arm64 tarball exists (HTTP $arm64_code)"
  else
    fail linux C4 "arm64 tarball" "Linux arm64 tarball not found for v${cli_version} (HTTP $arm64_code)"
  fi

  # C5: arm64 SHA256 sidecar valid
  local arm64_sha_content="" arm64_sha_code arm64_sha_valid=false
  local tmp_arm64_sha
  tmp_arm64_sha="$(mktemp)"
  arm64_sha_code=$(curl "${CURL_OPTS[@]}" -L -o "$tmp_arm64_sha" -w '%{http_code}' "$github_dl_base/${arm64_tarball}.sha256" 2>/dev/null) || true
  arm64_sha_content="$(cat "$tmp_arm64_sha" 2>/dev/null || true)"
  rm -f "$tmp_arm64_sha"

  local arm64_sha_hash
  arm64_sha_hash=$(echo "$arm64_sha_content" | head -1 | awk '{print $1}')
  if [ "$arm64_sha_code" = "200" ] && [[ "$arm64_sha_hash" =~ ^[0-9a-f]{64}$ ]]; then
    arm64_sha_valid=true
    pass linux C5 "arm64 SHA256 sidecar" "arm64 SHA256 sidecar valid"
  else
    fail linux C5 "arm64 SHA256 sidecar" "Linux arm64 SHA256 sidecar missing or invalid format (HTTP $arm64_sha_code)"
  fi

  # C6: SHA sidecar filename consistency
  # Only check filenames if at least one sidecar was valid
  if [ "$x86_sha_valid" = false ] && [ "$arm64_sha_valid" = false ]; then
    skip linux C6 "SHA sidecar filenames" "Skipped: no valid SHA256 sidecars to check"
    return
  fi

  local x86_sha_filename="" arm64_sha_filename=""
  if [ "$x86_sha_valid" = true ]; then
    x86_sha_filename=$(echo "$x86_sha_content" | head -1 | awk '{print $2}')
  fi
  if [ "$arm64_sha_valid" = true ]; then
    arm64_sha_filename=$(echo "$arm64_sha_content" | head -1 | awk '{print $2}')
  fi

  local filename_ok=true
  local mismatch_detail=""

  if [ -n "$x86_sha_filename" ] && [ "$x86_sha_filename" != "$x86_tarball" ]; then
    filename_ok=false
    mismatch_detail="x86_64 (expected: $x86_tarball, got: $x86_sha_filename)"
  fi
  if [ -n "$arm64_sha_filename" ] && [ "$arm64_sha_filename" != "$arm64_tarball" ]; then
    filename_ok=false
    if [ -n "$mismatch_detail" ]; then
      mismatch_detail="$mismatch_detail; arm64 (expected: $arm64_tarball, got: $arm64_sha_filename)"
    else
      mismatch_detail="arm64 (expected: $arm64_tarball, got: $arm64_sha_filename)"
    fi
  fi

  # Pass if sidecars have no filename component (hash-only format) or filenames match
  if [ -z "$x86_sha_filename" ] && [ -z "$arm64_sha_filename" ]; then
    pass linux C6 "SHA sidecar filenames" "SHA sidecar filenames consistent (hash-only format)"
  elif [ "$filename_ok" = true ]; then
    pass linux C6 "SHA sidecar filenames" "SHA sidecar filenames consistent"
  else
    fail linux C6 "SHA sidecar filenames" "SHA256 sidecar filename mismatch: $mismatch_detail"
  fi
}

# ── Section D: Cross-Surface Consistency ───────────────────────────────────────

run_consistency_checks() {
  section_header "D" "Cross-Surface Consistency"

  # D1: macos-version reachable and valid semver
  local macos_version macos_code
  local tmp_macos
  tmp_macos="$(mktemp)"
  macos_code=$(curl "${CURL_OPTS[@]}" -o "$tmp_macos" -w '%{http_code}' "$WEBSITE_BASE_URL/macos-version" 2>/dev/null) || true
  macos_version="$(tr -d '\r\n' < "$tmp_macos" 2>/dev/null || true)"
  rm -f "$tmp_macos"

  if [ "$macos_code" = "200" ] && [[ "$macos_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    VER_MACOS="$macos_version"
    pass consistency D1 "macos-version" "macos-version: $macos_version"
  else
    fail consistency D1 "macos-version" "macos-version unreachable or invalid semver (HTTP $macos_code)"
    skip consistency D2 "Appcast matches macos-version" "Skipped: prerequisite D1 failed"
    skip consistency D3 "DMG exists" "Skipped: prerequisite D1 failed"
    skip consistency D4 "Appcast URL pattern" "Skipped: prerequisite D1 failed"
    return
  fi

  # We need sparkle data. If sparkle section was not run, fetch it now.
  if [ -z "$VER_SPARKLE" ]; then
    local tmp_appcast_d
    tmp_appcast_d="$(mktemp)"
    local ac_code
    ac_code=$(curl "${CURL_OPTS[@]}" -o "$tmp_appcast_d" -w '%{http_code}' "$WEBSITE_BASE_URL/appcast.xml" 2>/dev/null) || true
    local ac_body
    ac_body="$(cat "$tmp_appcast_d" 2>/dev/null || true)"
    rm -f "$tmp_appcast_d"

    if [ "$ac_code" = "200" ] && [ -n "$ac_body" ]; then
      if command -v python3 &>/dev/null; then
        local d_parse
        d_parse=$(python3 -c "
import xml.etree.ElementTree as ET
import json, sys
xml_data = sys.stdin.read()
result = {'version': '', 'url': ''}
try:
    root = ET.fromstring(xml_data)
    ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    items = root.findall('.//item')
    if items:
        item = items[0]
        ver_el = item.find('sparkle:shortVersionString', ns)
        if ver_el is not None and ver_el.text:
            result['version'] = ver_el.text.strip()
        enc = item.find('enclosure')
        if enc is not None:
            result['url'] = enc.get('url', '')
            if not result['version']:
                result['version'] = enc.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString', '')
except Exception:
    pass
print(json.dumps(result))
" <<< "$ac_body" 2>/dev/null || echo '{}')
        VER_SPARKLE=$(echo "$d_parse" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || echo "")
        SPARKLE_URL_FOR_D=$(echo "$d_parse" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || echo "")
      else
        VER_SPARKLE=$(echo "$ac_body" | grep -o 'sparkle:shortVersionString="[^"]*"' | head -1 | sed 's/.*="//' | sed 's/"//')
        SPARKLE_URL_FOR_D=$(echo "$ac_body" | grep -o 'url="[^"]*"' | head -1 | sed 's/.*="//' | sed 's/"//')
      fi
    fi
  fi

  # D2: Appcast version matches macos-version
  if [ -n "$VER_SPARKLE" ]; then
    if [ "$VER_SPARKLE" = "$macos_version" ]; then
      pass consistency D2 "Appcast matches macos-version" "Appcast version matches macos-version"
    else
      fail consistency D2 "Appcast matches macos-version" "Appcast version ($VER_SPARKLE) does not match macos-version ($macos_version)"
    fi
  else
    fail consistency D2 "Appcast matches macos-version" "Could not determine appcast version for comparison"
  fi

  # D3: DMG exists on GitHub for macos-version
  local dmg_url="https://github.com/${GITHUB_RELEASE_REPO}/releases/download/v${macos_version}/Contextify.dmg"
  local dmg_code
  dmg_code=$(curl_code -I "$dmg_url")
  if [ "$dmg_code" = "302" ] || [ "$dmg_code" = "200" ]; then
    pass consistency D3 "DMG exists" "DMG exists on GitHub for v${macos_version} (HTTP $dmg_code)"
  else
    fail consistency D3 "DMG exists" "DMG not found on GitHub for v${macos_version} (HTTP $dmg_code)"
  fi

  # D4: Appcast URL follows expected pattern
  local expected_url="https://github.com/${GITHUB_RELEASE_REPO}/releases/download/v${VER_SPARKLE}/Contextify.dmg"
  if [ -n "${SPARKLE_URL_FOR_D:-}" ] && [ "$SPARKLE_URL_FOR_D" = "$expected_url" ]; then
    pass consistency D4 "Appcast URL pattern" "Appcast URL follows expected pattern"
  elif [ -z "${SPARKLE_URL_FOR_D:-}" ]; then
    fail consistency D4 "Appcast URL pattern" "Could not determine appcast enclosure URL"
  else
    fail consistency D4 "Appcast URL pattern" "Appcast enclosure URL does not follow expected GitHub pattern"
  fi
}

# ── Run Sections ───────────────────────────────────────────────────────────────

if [ "$JSON_MODE" = false ]; then
  echo ""
  printf "${BOLD}Live Systems Validation${NC}\n"
  echo "======================="
  echo "Run: $TIMESTAMP"
fi

# Initialize shared state for cross-section references
SPARKLE_URL_FOR_D=""

for section in "${SECTIONS[@]}"; do
  case "$section" in
    cloud)       run_cloud_checks ;;
    sparkle)     run_sparkle_checks ;;
    linux)       run_linux_checks ;;
    consistency) run_consistency_checks ;;
  esac
done

# ── Output ─────────────────────────────────────────────────────────────────────

if [ "$JSON_MODE" = true ]; then
  # Build JSON output using python3 for safe encoding
  overall_status="pass"
  if [ "$TOTAL_FAIL" -gt 0 ]; then
    overall_status="fail"
  fi

  # Build sections JSON
  sections_parts=""
  first_section=true

  for section in "${SECTIONS[@]}"; do
    if [ "$first_section" = false ]; then
      sections_parts="${sections_parts},"
    fi
    first_section=false

    s_pass=0; s_fail=0; s_checks_file=""
    case "$section" in
      cloud)       s_pass=$CLOUD_PASS; s_fail=$CLOUD_FAIL; s_checks_file="$TMP_DIR/cloud.json" ;;
      sparkle)     s_pass=$SPARKLE_PASS; s_fail=$SPARKLE_FAIL; s_checks_file="$TMP_DIR/sparkle.json" ;;
      linux)       s_pass=$LINUX_PASS; s_fail=$LINUX_FAIL; s_checks_file="$TMP_DIR/linux.json" ;;
      consistency) s_pass=$CONSISTENCY_PASS; s_fail=$CONSISTENCY_FAIL; s_checks_file="$TMP_DIR/consistency.json" ;;
    esac

    checks_array=$(build_json_array "$s_checks_file")
    sections_parts="${sections_parts}\"${section}\":{\"passed\":${s_pass},\"failed\":${s_fail},\"checks\":${checks_array}}"
  done

  cat <<ENDJSON
{
  "timestamp": "${TIMESTAMP}",
  "passed": ${TOTAL_PASS},
  "failed": ${TOTAL_FAIL},
  "status": "${overall_status}",
  "sections": {${sections_parts}},
  "versions": {
    "macos_version": "${VER_MACOS}",
    "cli_version": "${VER_CLI}",
    "sparkle_version": "${VER_SPARKLE}",
    "sparkle_build": "${VER_SPARKLE_BUILD}"
  }
}
ENDJSON
else
  # Human-readable summary
  echo ""
  echo "============================="
  skip_msg=""
  if [ "$TOTAL_SKIP" -gt 0 ]; then
    skip_msg=", ${TOTAL_SKIP} skipped"
  fi
  echo "Results: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed${skip_msg}"
  if [ "$TOTAL_FAIL" -eq 0 ]; then
    printf "${GREEN}${BOLD}VALIDATION PASSED${NC}\n"
  else
    printf "${RED}${BOLD}VALIDATION FAILED${NC}\n"
  fi
  echo ""
fi

# ── Exit ───────────────────────────────────────────────────────────────────────

if [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
