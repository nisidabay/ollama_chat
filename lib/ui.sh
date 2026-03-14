#!/usr/bin/env bash
# lib/ui.sh — LOLA UI helpers: banner, separators, styled output, help menu
# Guard: must be sourced, not executed directly
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || {
	echo "Source this file, don't run it directly." >&2
	exit 1
}

# Terminal width for dynamic sizing (use $COLUMNS if available, fallback to tput)
COLS="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"

# Styled banner: figlet LOLA title inside a gum double-border box
# Uses cached BANNER_OUTPUT from lola.sh to eliminate repeated figlet spawns
show_banner() {
	if [[ -n "$BANNER_OUTPUT" ]]; then
		gum style \
			--border double \
			--border-foreground 212 \
			--foreground 212 \
			--bold \
			--padding "0 2" \
			--margin "1 0" \
			"$BANNER_OUTPUT"
	else
		# Fallback (shouldn't happen, but defensive)
		local title
		title=$(figlet -f slant "LOLA" 2>/dev/null || echo "LOLA")
		gum style \
			--border double \
			--border-foreground 212 \
			--foreground 212 \
			--bold \
			--padding "0 2" \
			--margin "1 0" \
			"$title"
	fi
}

# Dim separator line spanning terminal width
ui_sep() {
	gum style --foreground 240 "$(printf '─%.0s' $(seq 1 "${COLS}"))"
}

# Styled key=value info line (label in purple, value in white)
ui_info() {
	local label="$1" value="$2"
	printf "%s %s\n" \
		"$(gum style --foreground 212 --bold "$label")" \
		"$(gum style --foreground 255 "$value")"
}

# Styled tip line (amber bullet + dim text)
ui_tip() {
	printf "%s %s\n" \
		"$(gum style --foreground 214 "◆")" \
		"$(gum style --foreground 245 "$*")"
}

# tmux session warning (red, bold)
running_tmux() {
	if [[ -n $TMUX ]]; then
		gum style --foreground 196 --bold "💻 THIS IS A TMUX SESSION  ·  Ctrl-C to quit 💻"
	fi
}

# Styled help menu rendered inside a rounded gum border
show_menu() {
	gum style \
		--border rounded \
		--border-foreground 212 \
		--padding "1 3" \
		--margin "1 0" \
		"$(
			cat <<MENU
LOLA — Local Ollama Language Assistant  v$VERSION

Usage
  !menu | !m         Show this help menu

History
  !history | !his    View the chat history
  !last              Copy last response to clipboard

Chat
  !load | !lo        Load a saved chat
  !save | !sa        Save current chat
  !edit_saved | !es  Edit a saved chat
  !new_chat | !new   Start a new chat
  !clear             Start a new chat
  !rm                Remove a saved chat

Models
  !switch | !sw      Switch AI model on the fly
  !sw_vision | !sv   Switch vision model on the fly

Helpers
  !web               Search the web
  !terminal | !t     Launch a new detached terminal
  !vision | !img     Analyze image (JPG/PNG only)
  !agent | !a        Switch agent persona

Script
  !edit_config | !ec Edit lola.conf inline
  !kill | !k         Stop Ollama and exit
  exit | quit        Quit the script

◆ Tip: Paste a block of text and press Ctrl+D to submit
MENU
		)"
}
