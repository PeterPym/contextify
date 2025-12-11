#!/bin/bash
# Test assertions for Contextify QA tests
# Source this file after common.sh: source "$(dirname "$0")/../lib/assertions.sh"

# Note: Requires common.sh to be sourced first for:
# - log_success, log_error functions
# - TEST_FAILED variable
# - LOGFILE variable
# - db_query, db_count functions

# ─────────────────────────────────────────────────────────────────────────────
# Filesystem Assertions
# ─────────────────────────────────────────────────────────────────────────────

assert_file_exists() {
  local file="$1"
  local desc="${2:-File exists: $file}"

  if [ -f "$file" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  File not found: $file"
    TEST_FAILED=1
    return 1
  fi
}

assert_file_not_exists() {
  local file="$1"
  local desc="${2:-File does not exist: $file}"

  if [ ! -f "$file" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  File should not exist: $file"
    TEST_FAILED=1
    return 1
  fi
}

assert_directory_exists() {
  local dir="$1"
  local desc="${2:-Directory exists: $dir}"

  if [ -d "$dir" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Directory not found: $dir"
    TEST_FAILED=1
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Process Assertions
# ─────────────────────────────────────────────────────────────────────────────

assert_app_running() {
  local app="${1:-Contextify}"
  local desc="${2:-App is running: $app}"

  if pgrep -x "$app" > /dev/null 2>&1; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Process not found: $app"
    TEST_FAILED=1
    return 1
  fi
}

assert_app_not_running() {
  local app="${1:-Contextify}"
  local desc="${2:-App is not running: $app}"

  if ! pgrep -x "$app" > /dev/null 2>&1; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Process should not be running: $app"
    TEST_FAILED=1
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Command Assertions
# ─────────────────────────────────────────────────────────────────────────────

assert_command_exists() {
  local cmd="$1"
  local desc="${2:-Command available: $cmd}"

  if command -v "$cmd" &> /dev/null; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Command not found: $cmd"
    TEST_FAILED=1
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Log Pattern Assertions
# ─────────────────────────────────────────────────────────────────────────────

assert_log_contains() {
  local pattern="$1"
  local desc="${2:-Log contains: $pattern}"

  if [ -z "${LOGFILE:-}" ]; then
    log_error "ASSERTION FAILED: $desc"
    log_error "  LOGFILE not set - call start_log_capture first"
    TEST_FAILED=1
    return 1
  fi

  if grep -q "$pattern" "$LOGFILE" 2>/dev/null; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected pattern: $pattern"
    log_error "  Log file: $LOGFILE"
    TEST_FAILED=1
    return 1
  fi
}

assert_log_not_contains() {
  local pattern="$1"
  local desc="${2:-Log does not contain: $pattern}"

  if [ -z "${LOGFILE:-}" ]; then
    log_error "ASSERTION FAILED: $desc"
    log_error "  LOGFILE not set"
    TEST_FAILED=1
    return 1
  fi

  if ! grep -q "$pattern" "$LOGFILE" 2>/dev/null; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Pattern should not appear: $pattern"
    TEST_FAILED=1
    return 1
  fi
}

assert_log_count() {
  local pattern="$1"
  local expected="$2"
  local desc="${3:-Log pattern count: $pattern = $expected}"

  if [ -z "${LOGFILE:-}" ]; then
    log_error "ASSERTION FAILED: $desc"
    log_error "  LOGFILE not set"
    TEST_FAILED=1
    return 1
  fi

  local actual
  actual=$(grep -c "$pattern" "$LOGFILE" 2>/dev/null || echo "0")

  if [ "$actual" = "$expected" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected $expected occurrences of: $pattern"
    log_error "  Got: $actual"
    TEST_FAILED=1
    return 1
  fi
}

assert_log_count_min() {
  local pattern="$1"
  local min="$2"
  local desc="${3:-Log pattern count >= $min: $pattern}"

  if [ -z "${LOGFILE:-}" ]; then
    log_error "ASSERTION FAILED: $desc"
    log_error "  LOGFILE not set"
    TEST_FAILED=1
    return 1
  fi

  local actual
  actual=$(grep -c "$pattern" "$LOGFILE" 2>/dev/null || echo "0")

  if [ "$actual" -ge "$min" ]; then
    log_success "✓ $desc (found $actual)"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected at least $min occurrences of: $pattern"
    log_error "  Got: $actual"
    TEST_FAILED=1
    return 1
  fi
}

assert_log_count_max() {
  local pattern="$1"
  local max="$2"
  local desc="${3:-Log pattern count <= $max: $pattern}"

  if [ -z "${LOGFILE:-}" ]; then
    log_error "ASSERTION FAILED: $desc"
    log_error "  LOGFILE not set"
    TEST_FAILED=1
    return 1
  fi

  local actual
  actual=$(grep -c "$pattern" "$LOGFILE" 2>/dev/null || echo "0")

  if [ "$actual" -le "$max" ]; then
    log_success "✓ $desc (found $actual)"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected at most $max occurrences of: $pattern"
    log_error "  Got: $actual"
    TEST_FAILED=1
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Database Assertions
# ─────────────────────────────────────────────────────────────────────────────

assert_db_exists() {
  local desc="${1:-Database file exists}"

  if [ -f "$DB_PATH" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Database not found: $DB_PATH"
    TEST_FAILED=1
    return 1
  fi
}

assert_db_count() {
  local query="$1"
  local expected="$2"
  local desc="${3:-Database count check}"

  local actual
  actual=$(db_count "$query")

  if [ "$actual" = "$expected" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected: $expected, Got: $actual"
    log_error "  Query: $query"
    TEST_FAILED=1
    return 1
  fi
}

assert_db_count_min() {
  local query="$1"
  local min="$2"
  local desc="${3:-Database count >= $min}"

  local actual
  actual=$(db_count "$query")

  if [ "$actual" -ge "$min" ]; then
    log_success "✓ $desc (count: $actual)"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected at least: $min, Got: $actual"
    log_error "  Query: $query"
    TEST_FAILED=1
    return 1
  fi
}

assert_db_count_max() {
  local query="$1"
  local max="$2"
  local desc="${3:-Database count <= $max}"

  local actual
  actual=$(db_count "$query")

  if [ "$actual" -le "$max" ]; then
    log_success "✓ $desc (count: $actual)"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected at most: $max, Got: $actual"
    log_error "  Query: $query"
    TEST_FAILED=1
    return 1
  fi
}

assert_db_row_exists() {
  local query="$1"
  local desc="${2:-Database row exists}"

  local result
  result=$(db_query "$query")

  if [ -n "$result" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Query returned no rows: $query"
    TEST_FAILED=1
    return 1
  fi
}

assert_db_row_not_exists() {
  local query="$1"
  local desc="${2:-Database row does not exist}"

  local result
  result=$(db_query "$query")

  if [ -z "$result" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Query should return no rows: $query"
    log_error "  Got: $result"
    TEST_FAILED=1
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Numeric Assertions
# ─────────────────────────────────────────────────────────────────────────────

assert_equals() {
  local expected="$1"
  local actual="$2"
  local desc="${3:-Values equal}"

  if [ "$expected" = "$actual" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected: $expected"
    log_error "  Actual: $actual"
    TEST_FAILED=1
    return 1
  fi
}

assert_not_equals() {
  local unexpected="$1"
  local actual="$2"
  local desc="${3:-Values not equal}"

  if [ "$unexpected" != "$actual" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Value should not be: $unexpected"
    TEST_FAILED=1
    return 1
  fi
}

assert_greater_than() {
  local value="$1"
  local threshold="$2"
  local desc="${3:-$value > $threshold}"

  if [ "$value" -gt "$threshold" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  $value is not greater than $threshold"
    TEST_FAILED=1
    return 1
  fi
}

assert_less_than() {
  local value="$1"
  local threshold="$2"
  local desc="${3:-$value < $threshold}"

  if [ "$value" -lt "$threshold" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  $value is not less than $threshold"
    TEST_FAILED=1
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# String Assertions
# ─────────────────────────────────────────────────────────────────────────────

assert_not_empty() {
  local value="$1"
  local desc="${2:-Value is not empty}"

  if [ -n "$value" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Value is empty"
    TEST_FAILED=1
    return 1
  fi
}

assert_empty() {
  local value="$1"
  local desc="${2:-Value is empty}"

  if [ -z "$value" ]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Value should be empty, got: $value"
    TEST_FAILED=1
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="${3:-String contains: $needle}"

  if [[ "$haystack" == *"$needle"* ]]; then
    log_success "✓ $desc"
    return 0
  else
    log_error "ASSERTION FAILED: $desc"
    log_error "  Expected to contain: $needle"
    log_error "  In: $haystack"
    TEST_FAILED=1
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Soft Assertions (log warning but don't fail)
# ─────────────────────────────────────────────────────────────────────────────

soft_assert_log_contains() {
  local pattern="$1"
  local desc="${2:-Log contains (soft): $pattern}"

  if [ -z "${LOGFILE:-}" ]; then
    log_warn "SOFT ASSERTION: $desc - LOGFILE not set"
    return 1
  fi

  if grep -q "$pattern" "$LOGFILE" 2>/dev/null; then
    log_success "✓ $desc"
    return 0
  else
    log_warn "SOFT ASSERTION: $desc - pattern not found"
    return 1
  fi
}

soft_assert_db_count_min() {
  local query="$1"
  local min="$2"
  local desc="${3:-Database count >= $min (soft)}"

  local actual
  actual=$(db_count "$query")

  if [ "$actual" -ge "$min" ]; then
    log_success "✓ $desc (count: $actual)"
    return 0
  else
    log_warn "SOFT ASSERTION: $desc - got $actual, expected >= $min"
    return 1
  fi
}
