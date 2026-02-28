#!/usr/bin/env bash
# lib/session.sh — LOLA session management: save, load, remove, edit saved chats
# Guard: must be sourced, not executed directly
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { echo "Source this file, don't run it directly." >&2; exit 1; }

# Save current chat to a named .txt file
handle_save() {
	local filename
	local confirm
	local dest

	read -rp "💾 Save current chat? (y/N) " confirm
	if [[ "${confirm,,}" =~ ^y(es)?$ ]]; then
		read -rp "💾 Save session as (default: chat_$(date +%Y%m%d_%H%M).txt): " filename

		# Default filename
		filename="${filename:-chat_$(date +%Y%m%d_%H%M).txt}"
		[[ "$filename" != *.txt ]] && filename="$filename.txt"

		dest="$LOLA_SESSION_DIR/$filename"

		if cp "$CHAT_HISTORY_FILE" "$dest" 2>/dev/null; then
			echo "✅ Saved to $dest"
		else
			echo "❌ Failed to save session" >&2
		fi
	else
		return
	fi
}

# Remove a saved chat session
handle_remove() {
	local load_chat
	local confirm

	if ! find "$LOLA_SESSION_DIR" -maxdepth 1 -type f -name "*.txt" -print -quit | read; then
		echo "📜 No chat sessions available to remove."
		return 1
	fi

	load_chat=$(find "$LOLA_SESSION_DIR" -maxdepth 1 -type f -name "*.txt" 2>/dev/null |
		menu "Remove chat: ")

	if [[ -z "$load_chat" ]]; then
		echo "📜 No chat selected."
		return 1
	fi

	if ! [[ -f "$load_chat" ]]; then
		echo "❌ File not found: $load_chat"
		return 1
	fi

	read -rp "🧹 Remove selected chat? (y/N) " confirm

	if [[ "${confirm,,}" =~ ^y(es)?$ ]]; then
		rm "$load_chat"
		echo "✅ Chat removed"
	else
		echo "❌ Removal cancelled" >&2
		return 1
	fi
}

# Edit a saved chat in the configured pager/editor
handle_edit_saved_chat() {
	local selected_file

	if ! find "$LOLA_SESSION_DIR" -maxdepth 1 -type f -name "*.txt" -print -quit | read; then
		echo "📜 No chat sessions available to edit."
		return 1
	fi

	selected_file=$(find "$LOLA_SESSION_DIR" -maxdepth 1 -type f -name "*.txt" 2>/dev/null |
		menu "Edit chat session: ")

	if [[ -z "$selected_file" ]]; then
		echo "📜 No chat selected."
		return 1
	fi

	if ! [[ -f "$selected_file" ]]; then
		echo "❌ File not found: $selected_file"
		return 1
	fi

	echo "✏️ Opening '$selected_file' in '$PAGER'..."
	"$PAGER" "$selected_file"
	echo "✅ Edit session ended."
}

# Load a saved chat session into the active history
handle_load() {
	local load_chat

	if ! find "$LOLA_SESSION_DIR" -maxdepth 1 -type f -name "*.txt" -print -quit | read; then
		echo "📜 No chat sessions available to restore."
		return 1
	fi

	load_chat=$(find "$LOLA_SESSION_DIR" -maxdepth 1 -type f -name "*.txt" 2>/dev/null |
		menu "Restore chat session: ")

	if [[ -z "$load_chat" ]]; then
		echo "📜 No chat selected."
		return 1
	fi

	if ! [[ -f "$load_chat" ]]; then
		echo "❌ No chat found: $load_chat"
		return 1
	fi

	if cp -f "$load_chat" "$CHAT_HISTORY_FILE"; then
		echo "✅ Session restored from ${load_chat##*/}"
	else
		echo "❌ Failed to restore session" >&2
		return 1
	fi
}

# Edit the configuration file inline
handle_edit_config() {
	echo "✏️ Opening '$CONFIG_FILE' in '${EDITOR:-vi}'..."
	"${EDITOR:-vi}" "$CONFIG_FILE"
	
	# Reload config after editing
	if [[ -f "$CONFIG_FILE" ]]; then
		#shellcheck disable=SC1090
		source "$CONFIG_FILE"
		echo "✅ Configuration reloaded."
	fi
}
