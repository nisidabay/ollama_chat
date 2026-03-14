#!/usr/bin/env bash
# lib/chat.sh — LOLA chat handlers: main conversation, history, clear, last
# Guard: must be sourced, not executed directly
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || {
	echo "Source this file, don't run it directly." >&2
	exit 1
}

# View chat history in the configured pager (read-only)
handle_history() {
	if [[ -s "$CHAT_HISTORY_FILE" ]]; then
		cat "$CHAT_HISTORY_FILE" | "$PAGER"
	else
		echo "📜 History is empty."
	fi
}

# Clear the chat history file
handle_clear() {
	: >"$CHAT_HISTORY_FILE"
	echo "📜 History has been cleared."
}

# Copy the last AI response to clipboard
handle_last() {
	local last_response

	# Extract the entire last AI response (everything after the *last* "🤖 AI:" marker)
	# Pure awk → 100% compatible with macOS (BSD) and Linux, no tail -r needed
	last_response=$(awk '
        /^🤖 AI:/ {
            # New AI response starts → reset buffer and skip the marker line itself
            buffer = ""
            next
        }
        {
            # Collect every following line until the end (or next AI marker)
            buffer = (buffer == "" ? $0 : buffer "\n" $0)
        }
        END {
            print buffer
        }
    ' "$CHAT_HISTORY_FILE" 2>/dev/null)

	if [[ -n "$last_response" ]]; then
		echo "$last_response" | $COPY_CMD
		echo "📋 Last response copied to clipboard."
	else
		echo "📜 No previous response found."
	fi
}

# Main chat interaction with Ollama
handle_chat() {
	local user_ask="$1"
	local full_prompt
	local conversation_history
	local response
	local formatted_response
	local LOG_PROMPT # Prompt stripped of ANSI codes for logging

	# Strip ANSI codes from PROMPT for logging
	# Note: Pure Bash不支持 regex, so sed is required for this complex pattern.
	# The pattern \x1b\[[0-9;]*[mGKH] matches ANSI escape sequences.
	LOG_PROMPT=$(echo "$PROMPT" | sed $'s/\x1b\\[[0-9;]*[mGKH]//g')

	# Use cached context line count instead of computing from config each time
	# Falls back to CONTEXT_LINES env/config, then 200 as ultimate default
	local effective_context_lines
	effective_context_lines="${CACHED_CONTEXT_LINES:-${CONTEXT_LINES:-200}}"

	# Read existing conversation from history file (limited to context window)
	if [[ -s "$CHAT_HISTORY_FILE" ]]; then
		conversation_history=$(tail -n "$effective_context_lines" "$CHAT_HISTORY_FILE")
	fi

	# Build prompt: honesty context + optional agent + history + user input
	# Use cached HONESTY_DATE from lola.sh startup (eliminates per-message date subprocess)
	local honesty_context="Current Date: $HONESTY_DATE. You are an AI model. If you do not know the answer or if the topic is too recent for your training data, admit it. Do not hallucinate."

	if [[ -n "$CURRENT_AGENT_CONTEXT" ]]; then
		full_prompt="System: $CURRENT_AGENT_CONTEXT"$'\n'"$honesty_context"$'\n\n'"$conversation_history"$'\n\n'"User request: $user_ask"
	else
		full_prompt="System: $honesty_context"$'\n\n'"$conversation_history"$'\n\n'"User request: $user_ask"
	fi

	# Run Ollama with a spinner covering the full pipeline
	local _tmpout
	_tmpout=$(mktemp)
	gum spin --spinner dot --title " Thinking..." -- \
		bash -c "ollama run \"\$1\" \"\$2\" | sed \$'s/\\x1b\\\\[[0-9;]*[mGKH]//g; s/.*\\r//' > \"\$3\"" -- "$MODEL" "$full_prompt" "$_tmpout"
	response=$(<"$_tmpout")
	rm -f "$_tmpout"

	if [[ -n "$response" ]]; then
		# Trim leading whitespace/newlines
		while [[ "$response" == $' '* ]]; do
			response="${response:1}"
		done

		# Format and display output
		formatted_response="🤖 AI: $response"
		echo -e "\n$formatted_response"

		# Copy response to clipboard (async to not block user input)
		(echo "$response" | $COPY_CMD) &

		# Desktop notification (macOS vs Linux) - async to not block user input
		if [[ "$(uname)" == "Darwin" ]]; then
			(osascript -e 'display notification "Response ready!" with title "LOLA"') &
		elif command -v notify-send &>/dev/null; then
			(notify-send -u normal "LOLA" "Response ready!" --icon=dialog-information) &
		fi

		echo
		ui_sep
		ui_tip "Response copied to clipboard  ·  !history to review the full chat"
		running_tmux
		ui_sep

		# Append new turn to history file
		printf "👦 %s %s\n\n%s\n\n" "$LOG_PROMPT" "$user_ask" "$formatted_response" >>"$CHAT_HISTORY_FILE"
	else
		echo "⚠️ Warning: Ollama returned an empty or filtered-out response."
	fi
}
