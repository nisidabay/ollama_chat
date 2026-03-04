# Changelog

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
