#!/usr/bin/env bash
# lib/helpers.sh — LOLA helpers: web search, terminal launcher, vision analysis, caching
# Guard: must be sourced, not executed directly
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || {
	echo "Source this file, don't run it directly." >&2
	exit 1
}

# ── Cache Directory Structure (XDG-compliant) ───────────────────────────────────
# Initialize cache directory at module load time
# Uses XDG_CACHE_HOME if set, falls back to ~/.cache
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/lola/cache"
mkdir -p "$CACHE_DIR" 2>/dev/null || {
	echo "⚠️  Warning: Could not create cache directory '$CACHE_DIR'" >&2
}

# ── Cache Functions ─────────────────────────────────────────────────────────────

# Get cached value if not expired
# @param $1 - Cache key
# @return 0 if found and valid, 1 if expired/missing
# @stdout Cached value (empty if not found)
# Cache files are stored as: key:expiry_epoch
cache_get() {
	local key="$1"
	local cache_file now expiry value

	# Find cache file matching pattern key:*
	for cache_file in "$CACHE_DIR/${key}:"*; do
		[[ -f "$cache_file" ]] || continue

		# Get current time
		now=$(date +%s)

		# Extract expiry epoch from filename (after the last colon)
		expiry="${cache_file##*:}"

		# Check if still valid
		if [[ "$now" -lt "$expiry" ]]; then
			# Valid cache — read and return content
			value=$(<"$cache_file")
			echo "$value"
			return 0
		else
			# Expired — delete and report miss
			rm -f "$cache_file" 2>/dev/null
			return 1
		fi
	done

	# No cache file found
	return 1
}

# Set cached value with TTL
# @param $1 - Cache key
# @param $2 - Value to cache
# @param $3 - TTL in seconds
cache_set() {
	local key="$1"
	local value="$2"
	local ttl_seconds="${3:-3600}" # Default 1 hour
	local now expiry cache_file

	now=$(date +%s)
	expiry=$((now + ttl_seconds))
	cache_file="$CACHE_DIR/${key}:${expiry}"

	# Remove old cache files for this key (handle special chars in keys)
	rm -f "$CACHE_DIR"/"${key}:"* 2>/dev/null

	# Write new value (use printf to handle multiline)
	printf '%s' "$value" >"$cache_file" 2>/dev/null || {
		echo "⚠️  Warning: Could not write to cache file" >&2
		return 1
	}
}

# Invalidate all cache or specific key
# @param $1 - Optional key; if empty, clears all cache files
cache_invalidate() {
	local key="$1"

	if [[ -n "$key" ]]; then
		rm -f "$CACHE_DIR"/"${key}:"* 2>/dev/null
	else
		rm -f "$CACHE_DIR"/* 2>/dev/null
	fi
}

# Compute optimal CONTEXT_LINES from a model's token context window.
# Queries the Ollama /api/show endpoint and returns: context_length / 40
# (50% of context ÷ ~20 tokens/line), capped at 5000.
# Falls back to 4096 tokens (→ 102 lines) on any error.
# Uses cache with 1-hour TTL to avoid repeated API calls.
auto_context_lines() {
	local model="$1"
	local cache_key="context:${model}"
	local cached response max_ctx safe_lines

	# Check cache first (1-hour TTL)
	cached=$(cache_get "$cache_key") && {
		echo "$cached"
		return
	}

	# Cache miss — query API
	response=$(curl -s --max-time 2 -X POST http://localhost:11434/api/show \
		-d "{\"name\": \"$model\"}" 2>/dev/null) || {
		echo 200
		return
	}

	if command -v jq >/dev/null 2>&1; then
		max_ctx=$(echo "$response" | jq -r \
			'.model_info | to_entries[] | select(.key | contains("context_length")) | .value' 2>/dev/null)
	else
		max_ctx=$(echo "$response" | grep -oP '"[^"]*context_length":\s*\K\d+')
	fi

	max_ctx=${max_ctx:-4096}
	safe_lines=$((max_ctx / 40))
	[[ "$safe_lines" -gt 5000 ]] && safe_lines=5000

	# Cache for 1 hour (model context window doesn't change frequently)
	cache_set "$cache_key" "$safe_lines" 3600

	echo "$safe_lines"
}

# Launch web search in the foreground (interactive — needs a TTY for gum)
handle_web() {
	bash "$WEB_SEARCH"
}

# Launch a new detached terminal
handle_terminal() {
	"$TERMINAL" &
}

# Analyze an image (JPG/PNG) using the configured vision model
handle_vision() {

	# Verify the vision model is installed (exact name match)
	if ! ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qxF "$VISION_MODEL"; then
		echo "⚠️  Vision model '$VISION_MODEL' is not installed."
		echo "💡 Install it with: ollama pull $VISION_MODEL"
		echo "💡 Then set VISION_MODEL in lola.conf"
		return 1
	fi

	# Fallback if IMAGE_DIR is not set or not a directory
	local search_dir="${IMAGE_DIR:-$HOME}"
	if [[ ! -d "$search_dir" ]]; then
		echo "⚠️  Configured IMAGE_DIR '$search_dir' does not exist. Falling back to $HOME"
		search_dir="$HOME"
	fi

	# Select image file using fzf
	local selected_file
	selected_file=$(find "$search_dir" -maxdepth 5 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null |
		fzf --prompt='Image: ' --height=40% --border)

	if [[ -z "$selected_file" ]]; then
		echo "Cancelled."
		return 0
	fi

	# Verify it's a valid image
	if ! file "$selected_file" | grep -q -E "jpeg|jpg|png"; then
		echo "❌ Error: '${selected_file##*/}' is not a valid image file."
		echo "💡 Please select JPG or PNG files only."
		return 1
	fi

	# Get user prompt
	echo ""
	read -rp "🔎 Describe what to analyze: " user_prompt
	if [[ -z "$user_prompt" ]]; then
		echo "Cancelled."
		return 0
	fi

	# Convert image to base64 (macOS vs Linux)
	echo "🧠 Analyzing with $VISION_MODEL..."
	local base64_data
	if [[ "$(uname)" == "Darwin" ]]; then
		base64_data=$(base64 "$selected_file")
	else
		base64_data=$(base64 "$selected_file" | tr -d '\n')
	fi

	# Use temp file for JSON payload to avoid "Argument list too long"
	local json_payload
	json_payload=$(mktemp)
	trap 'rm -f "$json_payload"' RETURN

	jq -n \
		--arg model "$VISION_MODEL" \
		--arg prompt "$user_prompt" \
		--arg img "$base64_data" \
		'{model: $model, prompt: $prompt, images: [$img], stream: false}' >"$json_payload"

	# Call vision model via REST API
	local response
	response=$(curl -s -X POST http://localhost:11434/api/generate \
		-H "Content-Type: application/json" \
		--data @"$json_payload" | jq -r '.response' 2>/dev/null)

	# Handle response
	if [[ -z "$response" || "$response" == "null" || "$response" == "unanswerable" ]]; then
		echo "⚠️ Vision model could not analyze the image."
		echo "💡 Tips: Use clearer images, avoid blurry/text-heavy screenshots"
	else
		local formatted_response="🤖 AI (Vision): $response"
		echo -e "\n$formatted_response"

		echo "$response" | $COPY_CMD
		echo "📋 Response copied to clipboard."

		local log_prompt="[Image: ${selected_file##*/}] $user_prompt"
		local LOG_PROMPT
		LOG_PROMPT=$(echo "$PROMPT" | sed $'s/\x1b\\[[0-9;]*[mGKH]//g')
		printf "👦 %s %s\n\n%s\n\n" "$LOG_PROMPT" "$log_prompt" "$formatted_response" >>"$CHAT_HISTORY_FILE"
	fi
}
