#!/usr/bin/env bash
# lib/models.sh — LOLA model management: get_model, get_vision_model, handle_agent, restart_ollama_server
# Guard: must be sourced, not executed directly
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || {
	echo "Source this file, don't run it directly." >&2
	exit 1
}

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
# Uses cache with 60-second TTL to avoid repeated ollama list calls
get_model() {
	local filter_models
	local selected_model
	local cache_key="models_list"
	local TTL_SECONDS=60

	# Try cache first
	filter_models=$(cache_get "$cache_key") || {
		# Cache miss — fetch from ollama
		filter_models=$(ollama list | awk 'NR>1 {print $1}') || {
			# ollama list failed — invalidate cache and report error
			cache_invalidate "$cache_key"
			echo "❌ Error: Failed to list models. Is Ollama running?" >&2
			return 1
		}

		# Cache the result
		if [[ -n "$filter_models" ]]; then
			cache_set "$cache_key" "$filter_models" "$TTL_SECONDS"
		fi
	}

	if [[ -z "$filter_models" ]]; then
		echo "❌ Error: No models available." >&2
		return 1
	fi

	selected_model=$(echo "$filter_models" | menu "Select Ollama Model: ")

	if [[ -z "$selected_model" ]]; then
		# Fall back to the MODEL set in config
		echo "$MODEL"
	else
		# Persist the new model to the config file
		# ^MODEL= anchors to start-of-line so VISION_MODEL= is never touched
		printf -v selected_model_quoted '"%s"' "$selected_model"
		if [[ "$(uname)" == "Darwin" ]]; then
			sed -i '' "s#^MODEL=.*#MODEL=$selected_model_quoted#" "$CONFIG_FILE"
		else
			sed -i "s#^MODEL=.*#MODEL=$selected_model_quoted#" "$CONFIG_FILE"
		fi
		echo "$selected_model"
	fi
}

# Select a vision-capable Ollama model and persist the choice to config
# Uses cache with 60-second TTL to avoid repeated ollama list calls
get_vision_model() {
	local all_models
	local filter_models
	local selected_model
	local cache_key="models_list"
	local TTL_SECONDS=60

	# Try cache first
	all_models=$(cache_get "$cache_key") || {
		# Cache miss — fetch from ollama
		all_models=$(ollama list | awk 'NR>1 {print $1}') || {
			# ollama list failed — invalidate cache and report error
			cache_invalidate "$cache_key"
			echo "❌ Error: Failed to list models. Is Ollama running?" >&2
			return 1
		}

		# Cache the result
		if [[ -n "$all_models" ]]; then
			cache_set "$cache_key" "$all_models" "$TTL_SECONDS"
		fi
	}

	if [[ -z "$all_models" ]]; then
		echo "❌ Error: No models available." >&2
		return 1
	fi

	# Pre-filter to known vision-capable model name patterns; fall back to all
	filter_models=$(echo "$all_models" | grep -iE "vision|llava|moondream|bakllava|minicpm|qwen.*vl|granite.*vision" 2>/dev/null)
	if [[ -z "$filter_models" ]]; then
		echo "⚠️  No vision models detected by name — showing all models."
		filter_models="$all_models"
	fi

	selected_model=$(echo "$filter_models" | menu "Select Vision Model: ")

	if [[ -z "$selected_model" ]]; then
		# Fall back to the VISION_MODEL set in config
		echo "$VISION_MODEL"
	else
		# Persist choice; ^VISION_MODEL= ensures MODEL= is never touched
		printf -v selected_model_quoted '"%s"' "$selected_model"
		if [[ "$(uname)" == "Darwin" ]]; then
			sed -i '' "s#^VISION_MODEL=.*#VISION_MODEL=$selected_model_quoted#" "$CONFIG_FILE"
		else
			sed -i "s#^VISION_MODEL=.*#VISION_MODEL=$selected_model_quoted#" "$CONFIG_FILE"
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
