# LOLA — Local Ollama Language Assistant

**LOLA** is a fast, private, terminal-based AI chat assistant powered by [Ollama](https://ollama.com).  
No API keys. No cloud. No fees. Everything runs locally on your machine.

> 💡 **Why LOLA?** Running AI locally means your conversations never leave your computer,
> there are no usage limits, and no monthly bills. The only cost is electricity.

---

## ✨ Features

- 🖥️ **Cross-Platform** — Works on Linux (X11/Wayland) and macOS.
- 🎨 **Rich terminal UI** — `figlet` ASCII banner, `gum`-styled borders, animated spinner
- 🖥️ **Unified inline menus** — `gum filter` fuzzy search, stays inside the
terminal on both X11 and Wayland
- 📋 **Auto clipboard** — every response is copied automatically (`wl-copy` / `xsel`)
- 💾 **Session management** — save, load, edit, and remove named chat sessions
- 🔄 **Live model switching** — swap models mid-conversation with `!switch`
- 🕵️ **Agent personas** — switch system prompts (Coder, Writer, Teacher…) with `!agent`
- 📅 **Honesty protocol** — current date injected; model instructed not to hallucinate
- 🖼️ **Vision analysis** — analyze images via a local vision model with `!vision`
- 🌐 **Web search** — launch a background web search with `!web`
- 📝 **Multi-line input** — paste a block of text and press `Ctrl+D` to submit
- 🗂️ **Modular codebase** — clean `lib/` structure, easy to extend

---

## 🖥️ Choosing a Model for Your Hardware

LOLA runs 100% locally — the right model depends on your GPU VRAM or system RAM.

| VRAM / RAM   | Recommended Model        | Notes                              |
|--------------|--------------------------|------------------------------------|
| CPU only     | `ministral-3b`           | Slow but works without a GPU       |
| < 4 GB       | `ministral-3b`           | Fast, minimal footprint            |
| 4–6 GB       | `llama3.2:latest`        | Great general-purpose model        |
| 6–8 GB       | `qwen2.5-coder:7b`       | Best for coding tasks              |
| 8–12 GB      | `qwen3:4b` / `mistral`   | Balanced speed + quality           |
| 12 GB+       | `llama3.1:8b` and above  | Near-GPT-4 quality, fully local    |

> 💡 Check your VRAM: `nvidia-smi` (NVIDIA) · `rocm-smi` (AMD) · `intel_gpu_top` (Intel)  
> 💡 Check your RAM: `free -h`

## Local models I use based on my hardware:
NAME                     ID              SIZE      MODIFIED    
devstral-small-2:24b     24277f07f62d    15 GB     12 days ago    
ministral-3:8b           1922accd5827    6.0 GB    12 days ago    
qwen3:4b                 359d7dd4bcda    2.5 GB    12 days ago    
granite3.2-vision:2b     3be41a661804    2.4 GB    2 weeks ago    
translategemma:latest    c49d986b0764    3.3 GB    2 weeks ago    
llama3.2:latest          a80c4f17acd5    2.0 GB    7 weeks ago    

---

## 📦 Installation

### 1. Install Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### 2. Pull a model (choose based on your hardware above)

```bash
ollama pull llama3.2:latest       # 4–6 GB VRAM
ollama pull qwen2.5-coder:7b      # 6–8 GB VRAM (great for coding)
ollama pull ministral-3b          # CPU / low VRAM
```

### 3. Install script dependencies

```bash
# macOS (using Homebrew)
brew install figlet fzf jq curl neovim gum

# Arch Linux
sudo pacman -S figlet fzf jq curl neovim xsel gum

# Debian / Ubuntu
sudo apt install figlet fzf jq curl neovim xsel
# gum is installed manually, see https://github.com/charmbracelet/gum#installation
```

### 4. Clone and run

```bash
git clone https://github.com/nisidabay/lola.git ~/bin/ollama_chat
chmod +x ~/bin/ollama_chat/lola.sh
~/bin/ollama_chat/lola.sh
```

---

## 🚀 Usage

```bash
./lola.sh
```

You'll see the **LOLA** ASCII banner, the active model, and a `❯` prompt.  
Type your question and press **Enter**. An animated spinner appears while the model thinks,  
then the response is printed and copied to your clipboard automatically.

Type `exit` or `quit` to leave cleanly.

---

## ⌨️ Commands

| Command                | Description                                          |
|------------------------|------------------------------------------------------|
| **Usage**              |                                                      |
| `!menu` / `!m`         | Show the help menu                                   |
| **History**            |                                                      |
| `!clear`               | Clear the chat history                               |
| `!history` / `!his`    | View the chat history                                |
| `!last`                | Copy last response to clipboard                      |
| **Chat**               |                                                      |
| `!load` / `!lo`        | Load a saved chat                                    |
| `!save` / `!sa`        | Save current chat                                    |
| `!edit_saved` / `!es`  | Edit a saved chat                                    |
| `!new_chat` / `!new`   | Start a new chat                                     |
| `!rm`                  | Remove a saved chat                                  |
| **Models**             |                                                      |
| `!switch` / `!sw`      | Switch AI model on the fly                           |
| **Helpers**            |                                                      |
| `!web`                 | Search the web                                       |
| `!terminal` / `!t`     | Launch a new detached terminal                       |
| `!vision` / `!img`     | Analyze image (JPG/PNG only)                         |
| `!agent` / `!a`        | Switch agent persona                                 |
| **Script**             |                                                      |
| `!edit_config` / `!ec` | Edit `lola.conf` inline                              |
| `!kill` / `!k`         | Stop Ollama server and exit                          |
| `exit` / `quit`        | Quit the script                                      |

---

## 🗂️ Project Structure

```
ollama_chat/
├── lola.sh       # Entry point (~140 lines)
├── web_search.sh           # Web search helper
└── lib/
    ├── ui.sh               # Banner, separators, styled output, help menu
    ├── chat.sh             # Main chat loop, history, clear, last
    ├── session.sh          # Save, load, remove, edit chat sessions
    ├── models.sh           # Model selection, agent switching, server restart
    └── helpers.sh          # Web search, terminal launcher, vision analysis
```

LOLA seamlessly stores your active configurations and sessions via the XDG Base Directory specification:
- **Configuration** (`lola.conf`): `~/.config/lola/lola.conf`
- **Session DB & History**: `~/.cache/lola/`

---

## ⚙️ Configuration

Edit `~/.config/lola/lola.conf` to customize, though MODEL is updated with the `!switch` | `!sw` commands:

```conf
MODEL="qwen3:4b"
VISION_MODEL="granite3.2-vision:2b"
EDITOR=nvim
PAGER=nvim

# Browser for web_search.sh (change to: chromium, brave, xdg-open, etc.)
BROWSER="firefox"

# Default directory for vision OCR images (leave empty to search $HOME)
IMAGE_DIR="$HOME/Pictures/Screenshots/"

# Search engines for web_search.sh
declare -A SEARCH_ENGINES_CONF
SEARCH_ENGINES_CONF[brave]="https://search.brave.com/search?q="
SEARCH_ENGINES_CONF[duck]="https://duckduckgo.com/?q="

# Agent system prompts
declare -A AGENTS_CONF
AGENTS_CONF[default]="You are a helpful assistant."
AGENTS_CONF[coder]="You are an expert software engineer."
AGENTS_CONF[writer]="You are a creative writer."
AGENTS_CONF[teacher]="You are a patient teacher."
AGENTS_CONF[concise]="Be extremely concise. Give only the answer, no filler."
```

---

## 🔧 Dependencies

| Tool       | Purpose                                  | Required      |
|------------|------------------------------------------|---------------|
| `ollama`   | Local LLM runtime                        | ✅ Yes        |
| `gum`      | Styled UI (spinner, menus, borders)      | ✅ Yes        |
| `figlet`   | ASCII banner                             | ✅ Yes        |
| `fzf`      | Image file picker for `!vision`          | ✅ Yes        |
| `jq`       | JSON parsing for vision API              | ✅ Yes        |
| `curl`     | Vision model API calls                   | ✅ Yes        |
| `nvim`     | Default pager/editor                     | ✅ Yes        |
| `pbcopy`   | Clipboard on macOS                       | macOS only    |
| `wl-copy`  | Clipboard on Wayland                     | Wayland only  |
| `foot`     | Terminal launcher on Wayland             | Wayland only  |
| `xsel`     | Clipboard on X11                         | X11 only      |
| `st`       | Terminal launcher on X11                 | X11 only      |

---

## 🛠️ Troubleshooting

| Problem                        | Fix                                              |
|--------------------------------|--------------------------------------------------|
| No models in `ollama list`     | Run `ollama pull llama3.2:latest`                |
| Model too slow                 | Switch to a smaller model (see hardware table)   |
| Clipboard not working          | Check `xsel` (X11), `wl-copy` (Wayland), or `pbcopy` (macOS) |
| Script exits prematurely       | Check Ollama is running: `pgrep ollama`          |
| Vision model not found         | Run `ollama pull <VISION_MODEL>`                 |
| Spinner flickers at start      | Ensure `gum` ≥ 0.14 is installed                |

---

## 📝 Notes

- In **tmux**, the prompt turns red and a warning is shown. Use **Ctrl+C** to quit.
- All chat logs are stored locally (`~/.cache/lola/`) — no internet required for chat.
- When switching models, the previous one is stopped cleanly via `ollama stop`.
- The script prompts for a model via `gum filter` if none is set in the config.

---

## 📄 License

MIT — see [LICENSE](LICENSE).
