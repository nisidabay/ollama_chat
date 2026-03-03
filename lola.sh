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

# ── Default config writer (first-run only) ───────────────────────────────────
write_default_config() {
	cat > "$CONFIG_FILE" <<'EOF'
# LOLA configuration — edit to suit your preferences.
# Generated automatically on first run.

MODEL=""
VISION_MODEL=""
EDITOR=nvim
PAGER=nvim

# Lines of chat history fed back to the model as context.
# Raise for large-context models (e.g. 128K), lower for small ones (e.g. 4K).
# A rough guide: ~50 lines per exchange; 200 = ~4 exchanges kept in context.
CONTEXT_LINES=200

# Terminal emulator launched by !terminal / !t
# Wayland examples: foot, kitty, alacritty, wezterm, ghostty
# X11 examples:     st, xterm, alacritty, urxvt
# macOS:            leave unset (defaults to "open -a Terminal")
TERMINAL="foot"

# Browser for web_search.sh (change to: chromium, brave, xdg-open, etc.)
BROWSER="firefox"

# Default directory for vision image picker (leave empty to search $HOME)
IMAGE_DIR="$HOME/Pictures/Screenshots/"

# Search engines for web_search.sh
declare -A SEARCH_ENGINES_CONF
SEARCH_ENGINES_CONF[brave]="https://search.brave.com/search?q="
SEARCH_ENGINES_CONF[duck]="https://duckduckgo.com/?q="
SEARCH_ENGINES_CONF[google]="https://www.google.com/search?q="
SEARCH_ENGINES_CONF[wikipedia]="https://en.wikipedia.org/wiki/"
SEARCH_ENGINES_CONF[github]="https://github.com/search?q="

# Agent system prompts
declare -A AGENTS_CONF
AGENTS_CONF[default]="You are a helpful assistant."
AGENTS_CONF[coder]="You are an expert software engineer. Provide clean, efficient code and explain your reasoning."
AGENTS_CONF[writer]="You are a creative writer. Craft engaging and imaginative content."
AGENTS_CONF[teacher]="You are a patient teacher. Explain concepts simply and clearly."
AGENTS_CONF[concise]="Be extremely concise. Give only the answer, no filler."
EOF
	echo "✅ Default config written to $CONFIG_FILE"
	echo "💡 Edit it to set your MODEL, VISION_MODEL, TERMINAL, and more."
	echo ""
}

# Load configuration — write defaults on first run
if [[ ! -f "$CONFIG_FILE" ]]; then
	write_default_config
fi
#shellcheck disable=SC1090
source "$CONFIG_FILE"

# Global state
CURRENT_AGENT_CONTEXT=""
VERSION='1.9'
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
# COPY_CMD is auto-detected from the display server.
# TERMINAL is read from lola.conf; a sane default is provided if unset.
# All menus use gum filter (pure terminal, identical on both).
if [[ "$(uname)" == "Darwin" ]]; then
	check_dependencies "pbcopy"
	TERMINAL="${TERMINAL:-open -a Terminal}"
	COPY_CMD="pbcopy"
elif [[ -n "$WAYLAND_DISPLAY" ]]; then
	check_dependencies "wl-copy"
	TERMINAL="${TERMINAL:-foot}"
	COPY_CMD="wl-copy"
else
	check_dependencies "xsel"
	TERMINAL="${TERMINAL:-st}"
	COPY_CMD="xsel -ib"
fi
# Verify the user-configured (or default) terminal emulator is present
check_dependencies "${TERMINAL%% *}"

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
			"!sw_vision" | "!sv")
				OLD_VISION="$VISION_MODEL"
				VISION_MODEL=$(get_vision_model)
				[[ -n "$OLD_VISION" && "$OLD_VISION" != "$VISION_MODEL" ]] && \
					ollama stop "$OLD_VISION" &>/dev/null
				#shellcheck disable=SC1090
				source "$CONFIG_FILE"
				echo "👁️  Vision model switched to $VISION_MODEL."
				;;
			"!save" | "!sa")       handle_save ;;
			"!load" | "!lo")       clear; handle_load ;;
			"!last")               handle_last ;;
			"!rm")                 handle_remove ;;
			"!web")                handle_web ;;
			"!terminal" | "!t")    handle_terminal ;;
			"!edit_config" | "!ec") handle_edit_config ;;
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
