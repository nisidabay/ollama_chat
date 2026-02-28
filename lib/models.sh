#!/usr/bin/env bash
# lib/models.sh — LOLA model management: get_model, handle_agent, restart_ollama_server
# Guard: must be sourced, not executed directly
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { echo "Source this file, don't run it directly." >&2; exit 1; }

# Restart the Ollama server
restart_ollama_server() {
	if pgrep -x "ollama" &>/dev/null; then
		echo "🛑 Shutting down Ollama server ..."
		if sudo pkill ollama; then
			echo "✅ Ollama server has been shut down."
			echo "✅ Ollama will be restarted automatically."
		else
			echo "❌ Failed to shut down Ollama server. Check sudo permissions." >&2
		fi
	else
		echo "🔴 Ollama server is not running."
	fi
}

# Select an Ollama model via gum filter and persist the choice to config
get_model() {
	local filter_models
	local selected_model

	filter_models=$(ollama list | awk 'NR>1 {print $1}')

	if [[ -z "$filter_models" ]]; then
		echo "❌ Error: No models available." >&2
		exit 1
	fi

	selected_model=$(echo "$filter_models" | menu "Select Ollama Model: ")

	if [[ -z "$selected_model" ]]; then
		# Fall back to the MODEL set in config
		echo "$MODEL"
	else
		# Persist the new model to the config file
		printf -v selected_model_quoted '"%s"' "$selected_model"
		if [[ "$(uname)" == "Darwin" ]]; then
			sed -i '' "s#MODEL=.*#MODEL=$selected_model_quoted#" "$CONFIG_FILE"
		else
			sed -i "s#MODEL=.*#MODEL=$selected_model_quoted#" "$CONFIG_FILE"
		fi
		echo "$selected_model"
	fi
}

# Switch agent persona via gum filter
handle_agent() {
	local selected_agent

	if [[ -z "${!AGENTS_CONF[*]}" ]]; then
		echo "⚠️ No agents defined in configuration."
		return 1
	fi

	selected_agent=$(printf '%s\n' "${!AGENTS_CONF[@]}" | menu "Select Agent: ")

	if [[ -z "$selected_agent" ]]; then
		echo "Cancelled."
		return 0
	fi

	if [[ -z "${AGENTS_CONF[$selected_agent]}" ]]; then
		echo "❌ Invalid agent selected."
		return 1
	fi

	CURRENT_AGENT_CONTEXT="${AGENTS_CONF[$selected_agent]}"
	echo "🕵️ Agent set to: $selected_agent"
	echo "📝 Context: $CURRENT_AGENT_CONTEXT"
}
