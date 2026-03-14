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
	cat >"$CONFIG_FILE" <<'EOF'
# LOLA configuration — edit to suit your preferences.
# Generated automatically on first run.

MODEL=""
VISION_MODEL=""
EDITOR=nvim
PAGER=nvim

# Lines of chat history fed back to the model as context.
# Set to "auto" to let LOLA detect the model's context window and calculate
# the optimal value automatically. Set a number (e.g. 200) to override.
CONTEXT_LINES=auto

# Terminal emulator launched by !terminal / !t
# Leave empty to auto-detect the first available emulator.
# Examples: foot, kitty, alacritty, wezterm, ghostty, st, xterm
# macOS:   leave empty (defaults to "open -a Terminal")
TERMINAL=""

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
CACHED_CONTEXT_LINES="" # Cached context line count per model (avoids repeated auto_context_lines calls)
VERSION='2.0'
PROMPT="You: "
touch "$CHAT_HISTORY_FILE"

# ── Dependency checker (parallel execution for faster startup) ──────────────────
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

# Check multiple groups in parallel for faster startup
# Groups run concurrently, but all failures are collected before exit
check_dependencies_fast() {
	local tmp_file
	tmp_file=$(mktemp)
	trap 'rm -f "$tmp_file"' RETURN

	# Run each dependency group in background, writing missing to temp file
	# Group each check to collect output to temp file
	(
		for prog in ollama gum figlet; do
			command -v "$prog" >/dev/null || echo "$prog" >>"$tmp_file"
		done
	) &
	local pid1=$!

	(
		for prog in nvim fzf jq; do
			command -v "$prog" >/dev/null || echo "$prog" >>"$tmp_file"
		done
	) &
	local pid2=$!

	(
		for prog in file curl; do
			command -v "$prog" >/dev/null || echo "$prog" >>"$tmp_file"
		done
	) &
	local pid3=$!

	# Wait for all background jobs to complete
	wait $pid1 $pid2 $pid3 2>/dev/null

	# Check if any dependencies were missing
	if [[ -s "$tmp_file" ]]; then
		local missing
		missing=$(tr '\n' ' ' <"$tmp_file" | sed 's/ $//')
		echo "❌ Missing dependencies: $missing" >&2
		exit 1
	fi
}

# Parallel dependency check (runs groups concurrently)
check_dependencies_parallel() {
	local missing_file
	missing_file=$(mktemp)

	# Run dependency checks in background groups
	(check_dependencies "ollama" "gum" "figlet" || echo "1" >"$missing_file") &
	local pid1=$!
	(check_dependencies "nvim" "fzf" "jq" || echo "1" >"$missing_file") &
	local pid2=$!
	(check_dependencies "file" "curl" || echo "1" >"$missing_file") &
	local pid3=$!

	# Wait for all background jobs
	wait $pid1 $pid2 $pid3 2>/dev/null

	# Check if any group failed
	if [[ -s "$missing_file" ]]; then
		rm -f "$missing_file"
		# Individual check already output error message
		exit 1
	fi

	rm -f "$missing_file"
}

# ── Environment detection (macOS vs Linux) ───────────────────────────────────
# COPY_CMD is auto-detected from the display server.
# TERMINAL is read from lola.conf; if empty, the first available emulator is used.
# All menus use gum filter (pure terminal, identical on both).
# Note: Platform-specific clipboard dependency check runs after fast parallel check
# because it's conditional on platform detection.

detect_clipboard_tool() {
	if [[ "$(uname)" == "Darwin" ]]; then
		command -v pbcopy >/dev/null || {
			echo "❌ pbcopy not found (required on macOS)." >&2
			exit 1
		}
		COPY_CMD="pbcopy"
	elif [[ -n "$WAYLAND_DISPLAY" ]]; then
		command -v wl-copy >/dev/null || {
			echo "❌ wl-copy not found (required on Wayland)." >&2
			exit 1
		}
		COPY_CMD="wl-copy"
	else
		command -v xsel >/dev/null || {
			echo "❌ xsel not found (required on X11)." >&2
			exit 1
		}
		COPY_CMD="xsel -ib"
	fi
}

detect_terminal() {
	if [[ "$(uname)" == "Darwin" ]]; then
		TERMINAL="${TERMINAL:-open -a Terminal}"
	elif [[ -n "$WAYLAND_DISPLAY" ]]; then
		if [[ -z "$TERMINAL" ]]; then
			for _term in foot kitty alacritty wezterm ghostty xterm; do
				if command -v "$_term" >/dev/null; then
					TERMINAL="$_term"
					break
				fi
			done
		fi
	else
		if [[ -z "$TERMINAL" ]]; then
			for _term in alacritty kitty st wezterm xterm; do
				if command -v "$_term" >/dev/null; then
					TERMINAL="$_term"
					break
				fi
			done
		fi
	fi
}

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

# Unified screen for new chats
startup_screen() {
	show_banner
	ui_info "◆ Model:" "$MODEL"
	ui_info "◆ Local Ollama Language Assistant" "v$VERSION"
	running_tmux
	ui_sep
	ui_tip "Type '!menu' for commands  ·  exit to quit"
	echo ""

}
# ── Main ─────────────────────────────────────────────────────────────────────
main() {
	local rest_of_input
	local full_prompt

	# Use parallel dependency check for faster startup
	check_dependencies_fast

	# Run environment detection
	detect_clipboard_tool
	detect_terminal

	# Cache performance-critical values at startup (eliminates per-message subprocess overhead)
	HONESTY_DATE=$(date +%Y-%m-%d)
	export HONESTY_DATE

	# Cache figlet banner output (eliminates repeated figlet spawns)
	BANNER_OUTPUT=$(figlet -f slant 'LOLA' 2>/dev/null || echo 'LOLA')
	export BANNER_OUTPUT

	# Cache visual prompts (eliminates per-loop gum style calls)
	VISUAL_PROMPT=$(gum style --foreground 212 --bold '❯ ')
	VISUAL_PROMPT_TMUX=$(gum style --foreground 196 --bold '❯ ')
	export VISUAL_PROMPT VISUAL_PROMPT_TMUX

	# Warn (don't exit) if no terminal emulator found — only !terminal is affected
	if [[ -z "$TERMINAL" ]]; then
		echo "⚠️  No terminal emulator found. Install one or set TERMINAL in lola.conf." >&2
	elif ! command -v "${TERMINAL%% *}" >/dev/null; then
		echo "⚠️  Terminal '$TERMINAL' not found. Install it or update TERMINAL in lola.conf." >&2
	fi

	# Red prompt in tmux sessions
	if [[ -n "$TMUX" ]]; then
		PROMPT=$'\e[31m'"$PROMPT"$'\e[0m'
	fi

	startup_screen

	# Pre-warm model list cache in background if no model configured
	# This hides latency during other startup operations
	if [[ -z "$MODEL" ]]; then
		(cache_get "models_list" >/dev/null 2>&1 || ollama list >/dev/null 2>&1) &
	fi

	# Prompt for model selection if none configured
	if [[ -z "$MODEL" ]]; then
		MODEL=$(get_model)
	fi

	# Auto-detect optimal CONTEXT_LINES from the model's context window
	if [[ "${CONTEXT_LINES}" == "auto" ]]; then
		CONTEXT_LINES=$(auto_context_lines "$MODEL")
		CACHED_CONTEXT_LINES="$CONTEXT_LINES" # Cache for per-message use
	fi

	# ── Interactive loop ──────────────────────────────────────────────────────
	while true; do
		local visual_prompt
		# Use cached visual prompt to avoid per-loop gum style calls
		if [[ -n "$TMUX" ]]; then
			visual_prompt="$VISUAL_PROMPT_TMUX"
		else
			visual_prompt="$VISUAL_PROMPT"
		fi

		read -rp "$visual_prompt" chat_line

		# Clean input: strip accidental "You:" prefix and leading whitespace
		local user_ask="${chat_line#"${chat_line%%[![:space:]]*}"}"
		# Strip "You:" prefix with optional trailing space (pure Bash)
		user_ask="${user_ask#You: }"
		user_ask="${user_ask#You:}"
		user_ask="${user_ask#"${user_ask%%[![:space:]]*}"}"

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
			"!menu" | "!m") show_menu ;;
			"!history" | "!his") handle_history ;;
			"!new_chat" | "!new" | "!clear")
				clear
				startup_screen
				handle_clear
				# Note: CACHED_CONTEXT_LINES is preserved — same model, same context window
				;;
			"!kill" | "!k")
				restart_ollama_server
				break
				;;
			"!switch" | "!sw")
				OLD_MODEL="$MODEL"
				MODEL=$(get_model)
				ollama stop "$OLD_MODEL" &>/dev/null
				#shellcheck disable=SC1090
				source "$CONFIG_FILE"
				# Recalculate context window for the new model
				if [[ "${CONTEXT_LINES}" == "auto" ]]; then
					CONTEXT_LINES=$(auto_context_lines "$MODEL")
					CACHED_CONTEXT_LINES="$CONTEXT_LINES" # Update cache for new model
				fi
				echo "🧠 Switched to $MODEL."
				;;
			"!sw_vision" | "!sv")
				OLD_VISION="$VISION_MODEL"
				VISION_MODEL=$(get_vision_model)
				[[ -n "$OLD_VISION" && "$OLD_VISION" != "$VISION_MODEL" ]] &&
					ollama stop "$OLD_VISION" &>/dev/null
				#shellcheck disable=SC1090
				source "$CONFIG_FILE"
				echo "👁️  Vision model switched to $VISION_MODEL."
				;;
			"!save" | "!sa") handle_save ;;
			"!load" | "!lo")
				clear
				handle_load
				;;
			"!last") handle_last ;;
			"!rm") handle_remove ;;
			"!web" | "!w") handle_web ;;
			"!terminal" | "!t") handle_terminal ;;
			"!edit_config" | "!ec") handle_edit_config ;;
			"!edit_saved" | "!es") handle_edit_saved_chat ;;
			"!vision" | "!img") handle_vision ;;
			"!agent" | "!a") handle_agent ;;

			"") continue ;;
			*) handle_chat "$user_ask" ;;
			esac
		fi
	done
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
