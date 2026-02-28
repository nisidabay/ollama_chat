# Changelog

## [1.8.0] - 2026-02-28

### Added

-   XDG Base Directory standard support. Configuration is now stored in `~/.config/lola` and cache/sessions in `~/.cache/lola`.
-   Context window protection limit. History appended to the context is now limited to the last 200 lines to prevent prompt window overflow on long sessions.

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
