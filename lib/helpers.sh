#!/usr/bin/env bash
# lib/helpers.sh — LOLA helpers: web search, terminal launcher, vision analysis
# Guard: must be sourced, not executed directly
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { echo "Source this file, don't run it directly." >&2; exit 1; }

# Launch web search in the foreground (interactive — needs a TTY for gum)
handle_web() {
	bash "$WEB_SEARCH"
}

# Launch a new detached terminal
handle_terminal() {
	setsid "$TERMINAL" >/dev/null 2>&1 &
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

	# Select image file using fzf
	local selected_file
	selected_file=$(find "$IMAGE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null |
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

	# Warn about large images (>5MB)
	local image_size
	image_size=$(stat -c%s "$selected_file" 2>/dev/null || stat -f%z "$selected_file" 2>/dev/null)
	if [[ "$image_size" -gt 5242880 ]]; then
		echo "⚠️ Large image ($(numfmt --to=iec-i --suffix=B "$image_size" 2>/dev/null || echo "${image_size}B"))"
		echo "💡 Resize to <5MB for better results"
	fi

	# Get user prompt
	echo ""
	read -rp "🔎 Describe what to analyze: " user_prompt
	if [[ -z "$user_prompt" ]]; then
		echo "Cancelled."
		return 0
	fi

	# Convert image to base64 (Linux base64 — no -i flag)
	echo "🧠 Analyzing with $VISION_MODEL..."
	local base64_data
	base64_data=$(base64 "$selected_file" | tr -d '\n')

	# Use temp file for JSON payload to avoid "Argument list too long"
	local json_payload
	json_payload=$(mktemp)
	trap 'rm -f "$json_payload"' RETURN

	cat >"$json_payload" <<EOF
{
  "model": "$VISION_MODEL",
  "prompt": "$user_prompt",
  "images": ["$base64_data"],
  "stream": false
}
EOF

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
