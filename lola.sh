#!/usr/bin/env bash
#
# lola.sh — LOLA: Local Ollama Language Assistant
#
# Entry point: loads config, sources lib modules, runs the main loop.
# All handler functions live in lib/*.sh for maintainability.
#
# Install Ollama:  curl -fsSL https://ollama.com/install.sh | sh
# Pull a model:    ollama pull llama3.2:latest  (or any model from ollama.com/library)

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# XDG Base Directory Support
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
LOLA_CONFIG_DIR="$XDG_CONFIG_HOME/lola"
LOLA_CACHE_DIR="$XDG_CACHE_HOME/lola"
LOLA_SESSION_DIR="$LOLA_CACHE_DIR/sessions"

# Create directories
mkdir -p "$LOLA_CONFIG_DIR"
mkdir -p "$LOLA_SESSION_DIR"

CONFIG_FILE="$LOLA_CONFIG_DIR/lola.conf"
CHAT_HISTORY_FILE="$LOLA_CACHE_DIR/history.log"

# Migrate old config/history if they exist in SCRIPT_DIR
if [[ -f "$SCRIPT_DIR/lola.conf" && ! -f "$CONFIG_FILE" ]]; then
	mv "$SCRIPT_DIR/lola.conf" "$CONFIG_FILE"
fi
if [[ -f "$SCRIPT_DIR/.lola_history.log" && ! -f "$CHAT_HISTORY_FILE" ]]; then
	mv "$SCRIPT_DIR/.lola_history.log" "$CHAT_HISTORY_FILE"
fi

WEB_SEARCH="$SCRIPT_DIR/web_search.sh"
IMAGE_DIR="$HOME/Pictures/Screenshots/"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
	#shellcheck disable=SC1090
	source "$CONFIG_FILE"
fi

# Global state
CURRENT_AGENT_CONTEXT=""
VERSION='1.8'
PROMPT="You: "
touch "$CHAT_HISTORY_FILE"

# ── Dependency checker ───────────────────────────────────────────────────────
check_dependencies() {
	local -a dependencies_array=("$@")
	local -a missing=()

	for program in "${dependencies_array[@]}"; do
		if ! command -v "$program" >/dev/null; then
			missing+=("$program")
		fi
	done

	if [[ "${#missing[@]}" -gt 0 ]]; then
		echo "❌ Missing dependencies: ${missing[*]}" >&2
		exit 1
	fi
}

# ── Environment detection (macOS vs Linux) ───────────────────────────────────
# Only TERMINAL and COPY_CMD differ per display server.
# All menus use gum filter (pure terminal, identical on both).
if [[ "$(uname)" == "Darwin" ]]; then
    check_dependencies "pbcopy"
    TERMINAL="open -a Terminal"
    COPY_CMD="pbcopy"
elif [[ -n "$WAYLAND_DISPLAY" ]]; then
	check_dependencies "foot" "wl-copy"
	TERMINAL="foot"
	COPY_CMD="wl-copy"
else
	check_dependencies "st" "xsel"
	TERMINAL="st"
	COPY_CMD="xsel -ib"
fi

# Unified inline fuzzy menu (gum filter — works on Wayland and X11)
menu() {
	local prompt="$1"
	gum filter --placeholder "$prompt" --height 15
}

# ── Source lib modules ───────────────────────────────────────────────────────
for _lib in ui chat session models helpers; do
	#shellcheck disable=SC1090
	source "$SCRIPT_DIR/lib/${_lib}.sh" || {
		echo "❌ Failed to load lib/${_lib}.sh" >&2
		exit 1
	}
done

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
	local rest_of_input
	local full_prompt

	check_dependencies "ollama" "gum" "figlet" "nvim" "fzf" "jq" "file" "curl"

	# Red prompt in tmux sessions
	if [[ -n "$TMUX" ]]; then
		PROMPT=$'\e[31m'"$PROMPT"$'\e[0m'
	fi

	show_banner
	ui_info "◆ Model:" "$MODEL"
	ui_info "◆ Local Ollama Language Assistant" "v$VERSION"
	running_tmux
	ui_sep
	ui_tip "Type '!menu' for commands  ·  exit to quit"
	echo ""

	# Prompt for model selection if none configured
	if [[ -z "$MODEL" ]]; then
		MODEL=$(get_model)
	fi

	# ── Interactive loop ──────────────────────────────────────────────────────
	while true; do
		local visual_prompt
		visual_prompt="$(gum style --foreground 212 --bold "❯") "
		if [[ -n "$TMUX" ]]; then
			visual_prompt="$(gum style --foreground 196 --bold "❯") "
		fi

		read -rp "$visual_prompt" chat_line

		# Clean input: strip accidental "You:" prefix and leading whitespace
		local user_ask
		user_ask=$(echo "$chat_line" | sed 's/^\s*You:\s*//; s/^\s*//')

		if [[ -z "$user_ask" ]]; then
			echo "⚠️ Empty input."
			continue
		fi

		# Multi-line paste (Ctrl+D)
		if read -t 0 -r _; then
			rest_of_input=$(cat)
			full_prompt="$user_ask"
			[[ -n "$rest_of_input" ]] && full_prompt+=$'\n'"$rest_of_input"
			handle_chat "$full_prompt"
		else
			case "$user_ask" in
			"exit" | "quit")
				[[ -n "$MODEL" ]] && ollama stop "$MODEL" &>/dev/null
				echo "👋 Goodbye!"
				break
				;;
			"!menu" | "!m")        show_menu ;;
			"!history" | "!his")   handle_history ;;
			"!clear")              handle_clear ;;
			"!new_chat" | "!new")  handle_clear; clear ;;
			"!kill" | "!k")        restart_ollama_server; break ;;
			"!switch" | "!sw")
				OLD_MODEL="$MODEL"
				MODEL=$(get_model)
				ollama stop "$OLD_MODEL" &>/dev/null
				#shellcheck disable=SC1090
				source "$CONFIG_FILE"
				echo "🧠 Switched to $MODEL."
				;;
			"!save" | "!sa")       handle_save ;;
			"!load" | "!lo")       clear; handle_load ;;
			"!last")               handle_last ;;
			"!rm")                 handle_remove ;;
			"!web")                handle_web ;;
			"!terminal" | "!t")    handle_terminal ;;
			"!edit_saved" | "!es") handle_edit_saved_chat ;;
			"!vision" | "!img")    handle_vision ;;
			"!agent" | "!a")       handle_agent ;;
			"")                    continue ;;
			*)                     handle_chat "$user_ask" ;;
			esac
		fi
	done
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
