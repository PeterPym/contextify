#!/bin/bash
# Fake Claude Code terminal output for screenshots
# Mimics the appearance of an active claude session
#
# Usage: ./fake-claude-session.sh [--minimal]
#
# Run this in the iTerm window that will appear in the screenshot.
# --minimal: shorter output for small terminal windows

# ANSI color codes (matching Claude Code's actual colors)
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
ITALIC="\033[3m"

# Claude Code colors
WHITE="\033[38;2;255;255;255m"           # RGB 255,255,255 for text
USER_BG="\033[48;2;55;55;55m"            # RGB 55,55,55 background for user lines
GREEN="\033[38;5;78m"                     # Green for success/checkmarks
GRAY="\033[38;5;245m"                     # Gray for metadata
RULE_GRAY="\033[38;2;68;68;68m"          # RGB 68,68,68 for horizontal rules
CYAN="\033[38;5;87m"                      # Cyan for tool names
ORANGE="\033[38;2;215;119;87m"           # RGB 215,119,87 for the monster

# Box drawing characters
BOX_TL="╭"
BOX_TR="╮"
BOX_BL="╰"
BOX_BR="╯"
BOX_H="─"
BOX_V="│"

# Set terminal title
printf "\033]0;✽ Implement dark mode\007"

clear

if [ "$1" = "--minimal" ]; then
  # Minimal: just the last exchange
  printf "${USER_BG}${WHITE}> Run the tests to make sure nothing broke.${RESET}\n"
  echo ""
  printf "  ${CYAN}Bash${RESET} ${DIM}swift test${RESET}\n"
  printf "    ${GREEN}✓${RESET} ${DIM}47 tests, 0 failures${RESET}\n"
  echo ""
  printf "${WHITE}⏺ All 47 tests passing. Build succeeded with zero warnings.${RESET}\n"
  echo ""
  printf "${USER_BG}${WHITE}> ${RESET}"
  while true; do sleep 1; done
fi

if [ "$1" = "--mixed-claude" ]; then
  # Claude Code session for mixed provider screenshot
  printf "\033]0;✽ Refactor auth module\007"
  clear
  echo ""
  printf "${ORANGE} ▐▛███▜▌${RESET}   ${WHITE}Claude Code${RESET} ${DIM}v2.0.53${RESET}\n"
  printf "${ORANGE}▝▜█████▛▘${RESET}  ${WHITE}Opus 4.5${RESET} ${DIM}· Claude Max${RESET}\n"
  printf "${ORANGE}  ▘▘ ▝▝${RESET}    ${DIM}~/code/projects/contextify${RESET}\n"
  echo ""
  printf "${USER_BG}${WHITE}> Refactor the auth module to use async/await${RESET}\n"
  echo ""
  printf "${WHITE}⏺ I'll refactor the authentication module to use modern async/await${RESET}\n"
  printf "${WHITE}  patterns throughout.${RESET}\n"
  echo ""
  printf "  ${CYAN}Edit${RESET} ${DIM}src/auth/AuthManager.swift${RESET}\n"
  printf "    ${GREEN}✓${RESET} ${DIM}Converted callbacks to async/await${RESET}\n"
  echo ""
  printf "  ${CYAN}Edit${RESET} ${DIM}src/auth/TokenRefresh.swift${RESET}\n"
  printf "    ${GREEN}✓${RESET} ${DIM}Updated token refresh flow${RESET}\n"
  echo ""
  printf "${WHITE}⏺ Auth module refactored. All 12 tests passing.${RESET}\n"
  echo ""
  printf "${USER_BG}${WHITE}> Add comprehensive error handling${RESET}\n"
  echo ""
  printf "${WHITE}⏺ I'll add proper error handling for network failures and token${RESET}\n"
  printf "${WHITE}  expiration scenarios.${RESET}\n"
  echo ""
  printf "  ${CYAN}Edit${RESET} ${DIM}src/auth/AuthManager.swift${RESET}\n"
  printf "    ${GREEN}✓${RESET} ${DIM}Added error handling for network failures${RESET}\n"
  echo ""
  printf "  ${CYAN}Edit${RESET} ${DIM}src/auth/TokenRefresh.swift${RESET}\n"
  printf "    ${GREEN}✓${RESET} ${DIM}Added token expiration recovery${RESET}\n"
  echo ""
  printf "${WHITE}⏺ Error handling complete. All edge cases covered.${RESET}\n"
  echo ""
  printf "${RULE_GRAY}%89s${RESET}\n" | tr ' ' '─'
  printf "${WHITE}> ${RESET}"
  while true; do sleep 1; done
fi

if [ "$1" = "--mixed-codex" ]; then
  # Codex session for mixed provider screenshot
  # Codex uses different styling - blue/teal theme
  CODEX_BLUE="\033[38;2;100;200;255m"

  printf "\033]0;Codex - Write auth tests\007"
  clear
  echo ""
  printf "${CODEX_BLUE}┌──────────────────────────────────────────┐${RESET}\n"
  printf "${CODEX_BLUE}│${RESET} ${WHITE}Codex CLI${RESET} ${DIM}v0.1.2${RESET}                        ${CODEX_BLUE}│${RESET}\n"
  printf "${CODEX_BLUE}│${RESET} ${DIM}~/code/projects/contextify${RESET}              ${CODEX_BLUE}│${RESET}\n"
  printf "${CODEX_BLUE}└──────────────────────────────────────────┘${RESET}\n"
  echo ""
  printf "${USER_BG}${WHITE}> Write unit tests for the auth module${RESET}\n"
  echo ""
  printf "${WHITE}⏺ I'll generate comprehensive tests for the authentication module.${RESET}\n"
  echo ""
  printf "  ${CYAN}Write${RESET} ${DIM}tests/auth/AuthManagerTests.swift${RESET}\n"
  printf "    ${GREEN}✓${RESET} ${DIM}Created 8 test cases${RESET}\n"
  echo ""
  printf "  ${CYAN}Write${RESET} ${DIM}tests/auth/TokenRefreshTests.swift${RESET}\n"
  printf "    ${GREEN}✓${RESET} ${DIM}Created 4 test cases${RESET}\n"
  echo ""
  printf "${WHITE}⏺ Generated 12 test cases covering auth flows, token refresh,${RESET}\n"
  printf "${WHITE}  and error handling. All tests passing.${RESET}\n"
  echo ""
  printf "${USER_BG}${WHITE}> ${RESET}"
  while true; do sleep 1; done
fi

# Full session display

# Print the Claude Code banner with monster
echo ""
printf "${ORANGE} ▐▛███▜▌${RESET}   ${WHITE}Claude Code${RESET} ${DIM}v2.0.53${RESET}\n"
printf "${ORANGE}▝▜█████▛▘${RESET}  ${WHITE}Opus 4.5${RESET} ${DIM}· Claude Max${RESET}\n"
printf "${ORANGE}  ▘▘ ▝▝${RESET}    ${DIM}~/code/projects/contextify${RESET}\n"
echo ""

# User prompt 1
printf "${USER_BG}${WHITE}> Add dark mode support to the settings panel${RESET}\n"
echo ""

# Claude's response with tool use indicators
printf "${WHITE}⏺ I'll add dark mode support to the settings panel. Let me update the${RESET}\n"
printf "${WHITE}  color tokens and theme configuration.${RESET}\n"
echo ""

# Tool use block
printf "  ${CYAN}Edit${RESET} ${DIM}Contextify/Theme.swift${RESET}\n"
printf "    ${GREEN}✓${RESET} ${DIM}Updated color tokens for dark mode${RESET}\n"
echo ""

printf "  ${CYAN}Edit${RESET} ${DIM}Contextify/SidebarView.swift${RESET}\n"
printf "    ${GREEN}✓${RESET} ${DIM}Fixed contrast in sidebar components${RESET}\n"
echo ""

# Claude completion message
printf "${WHITE}⏺ Dark mode implementation complete. All components now respect the${RESET}\n"
printf "${WHITE}  system appearance setting.${RESET}\n"
echo ""

# User prompt 2
printf "${USER_BG}${WHITE}> Looks great! Run the tests to make sure nothing broke.${RESET}\n"
echo ""

# Tool use for tests
printf "  ${CYAN}Bash${RESET} ${DIM}swift test${RESET}\n"
printf "    ${GREEN}✓${RESET} ${DIM}Executed 47 tests with 0 failures${RESET}\n"
echo ""

# Final response
printf "${WHITE}⏺ All 47 tests passing. Build succeeded with zero warnings.${RESET}\n"
echo ""

# Waiting prompt with horizontal rule above (full width)
printf "${RULE_GRAY}%89s${RESET}\n" | tr ' ' '─'
printf "${WHITE}> ${RESET}"

# Keep cursor blinking
while true; do
  sleep 1
done
