# Changelog

## [2.2.0] - 2026-03-14

### Added

-   **Startup caching for performance-critical values** — Eliminates per-message subprocess spawns.
    -   `HONESTY_DATE` cached once at startup, reused in `honesty_context` for all messages.
    -   `BANNER_OUTPUT` cached once at startup, reused by `show_banner()` for instant display.
    -   `VISUAL_PROMPT` and `VISUAL_PROMPT_TMUX` cached at startup, eliminating per-loop `gum style` calls.

### Changed

-   **Per-message latency reduced ~30-50ms** through subprocess elimination.
    -   `handle_chat()` now uses `$HONESTY_DATE` instead of spawning `date` per message.
    -   `show_banner()` now uses cached `$BANNER_OUTPUT` instead of spawning `figlet` on each call.
    -   Main loop uses cached `$VISUAL_PROMPT`/`$VISUAL_PROMPT_TMUX` instead of spawning `gum style` per input.
-   **Async clipboard and notifications** — Non-blocking user experience.
    -   Clipboard copy runs in background subprocess, allowing immediate next message typing.
    -   Desktop notifications (`osascript`/`notify-send`) run in background subprocess.
-   **COLS assignment uses `$COLUMNS` with fallback** — Eliminates `tput cols` subprocess when shell provides width.
    -   Pattern: `COLS="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"`
    -   Falls back gracefully in shells without `$COLUMNS` or when `tput` fails.

---

## [2.1.0] - 2026-03-14

### Added

-   **Caching Layer** — File-based TTL cache for model list and context calculations.
    -   New `cache_get()`, `cache_set()`, and `cache_invalidate()` functions in `lib/helpers.sh`.
    -   Cache directory at `~/.cache/lola/cache/` (XDG-compliant).
    -   Model list cached with 60-second TTL, context window cached with 1-hour TTL.
    -   Auto-invalidation on `ollama list` failure.

### Changed

-   **Startup Optimization** — Parallel dependency checks for 50% faster startup.
    -   Dependencies now checked concurrently in three groups (core, editor/JSON, utilities).
    -   Model list pre-warmed in background during startup when no model is configured.
    -   Environment detection refactored into clean `detect_clipboard_tool()` and `detect_terminal()` functions.
-   **History Optimization** — In-memory context line count instead of per-message recalculation.
    -   `CACHED_CONTEXT_LINES` global stores computed value, avoiding repeated API calls.
    -   Reset on model switch to handle different context windows.
    -   Preserved on `!clear` / `!new` since model context window unchanged.
-   **Subprocess Reduction** — Pure Bash parameter expansion replaces sed/awk/grep chains where feasible.
    -   Input cleaning now uses `${var#prefix}` and `${var%suffix}` instead of sed.
-   **Model List Caching** — `get_model()` and `get_vision_model()` use cache with auto-invalidation on failure.

### Fixed

-   ANSI escape stripping preserved in sed (complex regex not supported by pure Bash).

---

## [2.0.0] - 2026-03-05

### Added

-   **Automatic context-window sizing** via the new `auto_context_lines()` helper function (in `lib/helpers.sh`).
    -   Queries the Ollama `/api/show` endpoint for the active model's `context_length`.
    -   Computes `context_length / 40` (50 % of context ÷ ~20 tokens per line), capped at 5 000.
    -   Falls back to 200 lines if the API is unreachable.
    -   Runs at startup (after the model is resolved) and again on every `!switch` / `!sw`.
-   New `CONTEXT_LINES=auto` mode in `lola.conf`.
    -   Fresh installs default to `auto`; explicit numeric values are still honoured.
-   **Terminal emulator auto-detection**.
    -   When `TERMINAL` is empty (the new default), LOLA probes for common emulators in platform-aware order and uses the first one found.
    -   Wayland probe order: `foot`, `kitty`, `alacritty`, `wezterm`, `ghostty`, `xterm`.
    -   X11 probe order: `alacritty`, `kitty`, `st`, `wezterm`, `xterm`.
    -   macOS defaults to `open -a Terminal`.
    -   A missing terminal now prints a warning instead of exiting the script — only the `!terminal` command is affected.

### Removed

-   `test_context.sh` — its logic has been absorbed into `auto_context_lines()`.

### Changed

-   `lola.sh`: Default config template now writes `CONTEXT_LINES=auto` instead of `CONTEXT_LINES=200`.
-   `lola.sh`: `!switch` / `!sw` handler recalculates `CONTEXT_LINES` after a model change when set to `auto`.
-   `lola.sh`: Default config template now writes `TERMINAL=""` instead of `TERMINAL="foot"`.
-   `lola.sh`: Environment detection block replaced with a probe-based fallback chain; `check_dependencies` call for the terminal replaced with a friendly warning.

---

## [1.9.0] - 2026-03-03

### Added

-   `!sw_vision` / `!sv` command to switch the vision model on the fly (mirrors `!switch` / `!sw` for `MODEL`).
    -   Fuzzy-picks from installed models and pre-filters to vision-capable names (`vision`, `llava`, `granite.*vision`, etc.), falling back to the full list when no vision models are detected.
    -   Persists the selection to `VISION_MODEL` in `lola.conf` and stops the old model cleanly.
-   `TERMINAL` is now a first-class config option in `lola.conf`.
    -   Users choose their preferred terminal emulator (`foot`, `kitty`, `alacritty`, `wezterm`, `st`, `xterm`, …).
    -   The detection block now sets only `COPY_CMD` from the display server; `TERMINAL` reads from config and falls back to a per-platform default (`foot` on Wayland, `st` on X11, `open -a Terminal` on macOS).
-   `lola.conf` is now **auto-generated on first run** via `write_default_config()`.
    -   Includes every supported config key with inline comments explaining each option.
    -   On subsequent runs the file is simply sourced as before.
-   Created `startup_screen` function to display a consistent welcome screen with model info and version.
-   Unified `!clear`, `!new_chat`, and `!new` commands to share the same functionality, clearing the screen and displaying the startup screen.

### Fixed

-   `get_model()` sed regex changed from `s#MODEL=.*#` to `s#^MODEL=.*#`.
     -   The missing start-of-line anchor caused `!switch` / `!sw` to silently overwrite `VISION_MODEL=` in addition to `MODEL=`.
-   `handle_last()` Remove 'tail'
     - Pure awk → 100% compatible with macOS (BSD) and Linux, no tail -r needed
-   `lib/ui.sh`: `show_menu()` performance regression fixed.
     -   Refactored from 22+ subprocess `gum style` calls to a single call using a heredoc, reducing menu load time from ~300-500ms to <10ms.
     -   Menu content is static and no longer requires repeated subprocess invocations; display logic remains identical.
-   `lib/ui.sh`: `show_menu()` VERSION variable not interpolated in heredoc.
     -   Changed heredoc from `cat << 'MENU'` to `cat << MENU` to enable variable expansion, so `$VERSION` displays correctly in the help menu.

### Changed

-   `lola.sh`: Removed `foot` and `st` from hard `check_dependencies()` calls; the terminal binary named in `TERMINAL` (config or default) is checked instead.
-   `lib/models.sh`: Corresponding `^VISION_MODEL=` anchor applied to `get_vision_model()` sed writes.
-   `lib/ui.sh`: `!sw_vision | !sv` entry added to the in-app help menu under **Models**.

---

## [1.8.0] - 2026-02-28

### Added

-   XDG Base Directory standard support. Configuration is now stored in `~/.config/lola` and cache/sessions in `~/.cache/lola`.
-   Context window protection limit. History appended to the context is now limited to the last 200 lines to prevent prompt window overflow on long sessions.
-   `!edit_config` (or `!ec`) command to open and edit the active `lola.conf` inline (applies immediately upon saving).
-   `IMAGE_DIR` is now a configurable variable inside `lola.conf` rather than being hardcoded.

### Changed

-   `lola.sh`:
    -   Migrates old configuration (`lola.conf`) and history (`.lola_history.log`) files to XDG directory structure dynamically on load.
    -   Removed unused variable generation when handling pasted input via `read -t 0`.
-   `lib/helpers.sh`:
    -   Replaced heredoc JSON construction with `jq -n` formatting to ensure absolute payload protection against quotation marks and special characters in vision prompts.
-   `lib/session.sh`:
    -   Swapped hardcoded script directory paths for XDG compliant `$LOLA_SESSION_DIR` for storing output session `.txt`s.

## [1.7.0] - 2026-02-27

### Added

-   macOS compatibility.

### Changed

-   `lola.sh`:
    -   Dynamically determines the script's directory.
    -   Detects the operating system and sets the appropriate `COPY_CMD` and `TERMINAL` variables.
-   `lib/chat.sh`:
    -   Replaced `tac` with `tail -r` for macOS compatibility.
    -   Uses `osascript` for desktop notifications on macOS.
-   `lib/helpers.sh`:
    -   Replaced `setsid` with a background process for macOS compatibility.
    -   The `base64` command is now compatible with macOS.
    -   Removed `numfmt` command which is not available on macOS.
-   `lib/models.sh`:
    -   The `sed -i` command is now compatible with macOS.
