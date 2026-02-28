#!/usr/bin/env bash
#
# web_search.sh — LOLA web search helper
#
# Launched by lola.sh via !web
# Uses gum for inline terminal menus (Wayland and X11 compatible)
# Pure Bash — no python or external URL encoders needed

# Determine the directory of the current script
SCRIPT_DIR_WEB="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIG_FILE="$XDG_CONFIG_HOME/lola/lola.conf"

# Source the configuration file
if [[ -f "$CONFIG_FILE" ]]; then
	#shellcheck disable=SC1090
	source "$CONFIG_FILE"
else
	echo "⚠️ Warning: Config file '$CONFIG_FILE' not found. Using defaults." >&2
fi

# Fallback search engines if none defined in config
if [[ -z "${!SEARCH_ENGINES_CONF[*]}" ]]; then
	declare -A SEARCH_ENGINES_CONF
	SEARCH_ENGINES_CONF[brave]="https://search.brave.com/search?q="
	SEARCH_ENGINES_CONF[google]="https://www.google.com/search?q="
	SEARCH_ENGINES_CONF[duck]="https://duckduckgo.com/?q="
	echo "ℹ️ Using default search engines." >&2
fi

# Fallback browser if not set in config
BROWSER="${BROWSER:-xdg-open}"

# Unified inline fuzzy menu — works on both Wayland and X11
menu() {
	local prompt="$1"
	gum filter --placeholder "$prompt" --height 15
}

# Pure Bash URL encoding — no external tools needed
url_encode() {
	local string="$1"
	local encoded=""
	local i c o
	for (( i=0; i<${#string}; i++ )); do
		c="${string:$i:1}"
		case "$c" in
			[a-zA-Z0-9.~_-]) encoded+="$c" ;;
			' ') encoded+='+' ;;
			*) printf -v o '%%%02X' "'$c"
			   encoded+="$o" ;;
		esac
	done
	echo "$encoded"
}

# Get user query via gum input
get_query() {
	local query
	query=$(gum input --placeholder "Search what?" --prompt "🔎 ")

	if [[ -z "$query" ]]; then
		return 1
	fi
	echo "$query"
}

# Select search engine and open URL in browser
get_engine() {
	local query="$1"
	local selected_engine
	local url

	selected_engine=$(printf '%s\n' "${!SEARCH_ENGINES_CONF[@]}" | menu "Select Engine: ")

	if [[ -z "$selected_engine" ]]; then
		return 1
	fi

	if [[ -z "${SEARCH_ENGINES_CONF[$selected_engine]}" ]]; then
		echo "❌ Invalid engine selected." >&2
		return 1
	fi

	url="${SEARCH_ENGINES_CONF[$selected_engine]}$(url_encode "$query")"

	# Open in configured browser (detached)
	"${BROWSER}" "${url}" &>/dev/null &
}

main() {
	local query
	query=$(get_query)

	if [[ -n "$query" ]]; then
		get_engine "$query"
	else
		echo "❌ No query entered."
	fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main
fi
