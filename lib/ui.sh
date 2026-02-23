#!/usr/bin/env bash
# lib/ui.sh — LOLA UI helpers: banner, separators, styled output, help menu
# Guard: must be sourced, not executed directly
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { echo "Source this file, don't run it directly." >&2; exit 1; }

# Terminal width for dynamic sizing
COLS=$(tput cols 2>/dev/null || echo 80)

# Styled banner: figlet LOLA title inside a gum double-border box
show_banner() {
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
	local menu_content
	menu_content=$(
		gum style --foreground 212 --bold "LOLA — Local Ollama Language Assistant  v$VERSION"
		echo ""
		gum style --foreground 212 --bold "Usage"
		gum style --foreground 245 "  !menu | !m         Show this help menu"
		echo ""
		gum style --foreground 212 --bold "History"
		gum style --foreground 245 "  !clear             Clear the chat history"
		gum style --foreground 245 "  !history | !his    View the chat history"
		gum style --foreground 245 "  !last              Copy last response to clipboard"
		echo ""
		gum style --foreground 212 --bold "Chat"
		gum style --foreground 245 "  !load | !lo        Load a saved chat"
		gum style --foreground 245 "  !save | !sa        Save current chat"
		gum style --foreground 245 "  !edit_saved | !es  Edit a saved chat"
		gum style --foreground 245 "  !new_chat | !new   Start a new chat"
		gum style --foreground 245 "  !rm                Remove a saved chat"
		echo ""
		gum style --foreground 212 --bold "Models"
		gum style --foreground 245 "  !switch | !sw      Switch AI model on the fly"
		echo ""
		gum style --foreground 212 --bold "Helpers"
		gum style --foreground 245 "  !web               Search the web"
		gum style --foreground 245 "  !terminal | !t     Launch a new detached terminal"
		gum style --foreground 245 "  !vision | !img     Analyze image (JPG/PNG only)"
		gum style --foreground 245 "  !agent | !a        Switch agent persona"
		echo ""
		gum style --foreground 212 --bold "Script"
		gum style --foreground 245 "  !kill | !k         Stop Ollama and exit"
		gum style --foreground 245 "  exit | quit        Quit the script"
		echo ""
		gum style --foreground 214 "◆ Tip: Paste a block of text and press Ctrl+D to submit"
	)
	gum style \
		--border rounded \
		--border-foreground 212 \
		--padding "1 3" \
		--margin "1 0" \
		"$menu_content"
}
