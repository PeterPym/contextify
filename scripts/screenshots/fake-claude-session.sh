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

# Waiting prompt
printf "${USER_BG}${WHITE}> ${RESET}"

# Keep cursor blinking
while true; do
  sleep 1
done
