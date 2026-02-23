#!/usr/bin/env bash
# lib/chat.sh — LOLA chat handlers: main conversation, history, clear, last
# Guard: must be sourced, not executed directly
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { echo "Source this file, don't run it directly." >&2; exit 1; }

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

	# Extract last AI response (after last "🤖 AI:" marker)
	last_response=$(tac "$CHAT_HISTORY_FILE" 2>/dev/null |
		awk '/^🤖 AI:/ {p=1; next} p && NF {print; exit}' | tac)

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
	LOG_PROMPT=$(echo "$PROMPT" | sed $'s/\x1b\\[[0-9;]*[mGKH]//g')

	# Read existing conversation from history file (safe, non-destructive)
	if [[ -s "$CHAT_HISTORY_FILE" ]]; then
		conversation_history=$(<"$CHAT_HISTORY_FILE")
	fi

	# Build prompt: honesty context + optional agent + history + user input
	local honesty_context="Current Date: $(date +%Y-%m-%d). You are an AI model. If you do not know the answer or if the topic is too recent for your training data, admit it. Do not hallucinate."

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

		# Copy response to clipboard
		echo "$response" | $COPY_CMD

		# Desktop notification (only if notify-send is available)
		command -v notify-send &>/dev/null && \
			notify-send -u normal "LOLA" "Response ready!" --icon=dialog-information

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
