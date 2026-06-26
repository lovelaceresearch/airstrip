# Airstrip

Airstrip is a macOS SwiftUI launcher for local Python and Ollama automations.

The intended user flow is:

1. Download Airstrip.
2. Drop an automation folder or file into the app.
3. Airstrip copies it into `~/Library/Application Support/Airstrip/Projects`.
4. The automation appears as an icon on the springboard.
5. Double-click the icon to run it, or click it to view logs.

## Status Sidebar & Dashboard

Airstrip features a collapsible status sidebar on the left side of the window, toggled via the status check button in the toolbar. The sidebar displays cards in the following order:

- **Running Apps/Servers** — Lists all currently running Airstrip projects with stop controls.
- **Runtime** — Python, Homebrew, and Ollama status checks with one-click installs, plus an on/off switch for the local Ollama server.
- **Help/Guide** — A detailed guide on what types of projects Airstrip can run, including a folder checker to grade folders before importing.
- **Active Ports** — A real-time TCP port scanner listing active ports >= 80, showing whether they are owned by an Airstrip project (with a Stop button) or by an external system process (with a Kill button).
- **Activity** — Overall stats showing the count of running apps and completed runs.

Projects added or removed in Finder are picked up automatically whenever Airstrip becomes the active app.

## Built-in AI Studio

The springboard includes an integrated "AI Studio" chat app that opens in its own tab like any other project:

- If Ollama is installed but not running, Airstrip starts `ollama serve` itself (and stops it again on quit if it started it).
- Cloud models work too: add API keys for OpenAI, Gemini, Claude, or Mistral in the settings sheet. Keys live in the macOS Keychain.
- Pick a model from the picker in the input bar; you can switch models mid-conversation and the history carries over.
- Press the + button next to the model picker to send the same prompt to several models — local and cloud mixed — at once. The tab splits into one column per model and all responses stream live.
- The settings sheet covers the persona (system prompt shared by all models) and generation parameters: temperature, top-p, repeat penalty, context window, seed, and keep-alive. "Show response stats" prints token counts and speed under each answer, like `ollama --verbose`.

## Project Manifest

Automation folders can include an `airstrip.json` file:

```json
{
  "name": "Invoice Assistant",
  "icon": "icon.png",
  "run": "python app.py",
  "actions": [
    {
      "name": "Run Demo",
      "command": "python app.py --demo",
      "isDefault": true
    },
    {
      "name": "Export JSON",
      "command": "python app.py --json"
    },
    {
      "name": "Start UI",
      "command": "streamlit run streamlit_app.py --server.port $PORT",
      "web": {
        "port": 8501,
        "openPath": "/",
        "openOnStart": true,
        "allowPortFallback": true
      }
    }
  ],
  "requirements": "requirements.txt",
  "tools": [
    {
      "command": "pdftoppm",
      "brew": "poppler"
    }
  ],
  "ollama": {
    "models": ["llama3.1:8b"]
  }
}
```

If no manifest exists, Airstrip looks for runnable commands in `README.md`, then falls back to `main.py`, `app.py`, `streamlit_app.py`, or `app/main.py`.

Use `run` for a single default command. Use `actions` when one folder exposes multiple useful commands. Double-click runs the default action; right-click shows all actions.

For local web servers, add `web` to an action. Airstrip checks the port before launch, falls back to the next available port when allowed, sets `PORT` and `AIRSTRIP_PORT` in the process environment, replaces `{PORT}` in the command string, opens the browser, and kills the selected port when stopping the project.

Examples:

```json
{
  "name": "Start Streamlit",
  "command": "streamlit run streamlit_app.py --server.port $PORT",
  "web": {
    "port": 8501,
    "openOnStart": true,
    "allowPortFallback": true
  }
}
```

```json
{
  "name": "Start FastAPI",
  "command": "uvicorn app.main:app --host 127.0.0.1 --port {PORT}",
  "web": {
    "port": 8000,
    "openPath": "/docs"
  }
}
```

For Python actions, Airstrip creates a project-local `.airstrip-venv` so commands can safely use `python` even on Macs where only `python3` exists globally. A venv that was copied from another machine is detected as broken and rebuilt automatically.

When `requirements` is present, Airstrip installs the packages into that project-local environment before running the action. The install is skipped on later runs until the requirements file changes, so repeat runs start instantly and work offline.

When `tools` is present, Airstrip checks that each command-line tool exists before running. If something is missing, the project console shows a banner with a one-click install button that opens Terminal and runs the Homebrew install (bootstrapping Homebrew first when needed). This is how a project declares system dependencies such as `pdftoppm` from `poppler`.

When Ollama models are listed, Airstrip runs `ollama pull` before launching the project.

Stopping a project kills the entire process tree, including child processes the shell spawned, plus anything still listening on the project's web port.

## Current MVP

- SwiftUI springboard UI with Liquid Glass panel design
- Dynamic tab sizing system with hit-testing click targets
- File/Folder drag-and-drop and select dialog import
- Consolidated toolbar controls (Import, Runtime Status, Navigation)
- Left Status Sidebar with port scanner, stop/kill controls, and runtime setup
- Per-project run, stop, logs, and Finder reveal
- Dependency detection for Python, Homebrew, and Ollama
- Homebrew install via visible Terminal script
- Ollama install via Homebrew when available, otherwise the official macOS download page
- AI Studio for local Ollama chat plus optional OpenAI, Gemini, Claude, and Mistral API keys

## What Airstrip Can Run

Airstrip is best for local automation folders that expose one or more commands:

- Python scripts, including project-local virtual environments and `requirements.txt`
- Shell commands declared in `airstrip.json`
- Local web apps such as Streamlit, FastAPI, Flask, or any command that starts a server on a port
- Ollama-backed projects that declare required local models

It is not intended to run Windows/Linux-only binaries, repos with no runnable command, or tools that need admin-level installation unless the project declares those dependencies clearly.

The Runtime popover includes a runability checker that summarizes imported projects and highlights obvious missing pieces such as Python, Ollama, or declared command-line tools.

## AI Studio

The built-in AI Studio can talk to local Ollama models and external providers. Add OpenAI, Gemini, Claude, or Mistral keys from AI Studio settings. API keys are stored in the macOS Keychain; model IDs stay editable because provider model names change over time.

## Install On Another Mac

To put Airstrip plus an automation on someone else's Mac:

1. On your Mac, run `Scripts/package-app.sh`. It builds a Release app and produces `dist/Airstrip.zip`.
2. AirDrop `Airstrip.zip` and the automation folder to the other Mac. Airstrip skips `.airstrip-venv`, caches, and `.git` during import, so the raw folder is fine to send as-is.
3. On the other Mac: unzip, drag `Airstrip.app` into Applications, right-click it, and choose Open (first launch only; the app is not notarized).
4. Open Airstrip and drag the automation folder into the window.
5. Double-click the project icon. If Python or a required tool is missing, Airstrip shows install buttons; each one opens Terminal, installs the dependency, and then Run works.

The first run of a Python project takes longer because the environment is created and packages are installed. Later runs skip that step.

## Run During Development

Open `Airstrip.xcodeproj` in Xcode and run the `Airstrip` scheme.

The `Package.swift` target is kept as a lightweight command-line build path, but the Xcode project is the real macOS `.app` bundle. Use the Xcode project when you want a normal windowed app.

```sh
swift run
```

## Documentation

- [Design System & Aesthetics](file:///Users/chanwoo/Documents/xcode/airstrip/docs/design.md) - Details on Liquid Glass panel and custom SwiftUI designs.
- [Import & Bootstrapping Workflow](file:///Users/chanwoo/Documents/xcode/airstrip/docs/IMPORT_WORKFLOW.md) - Details on file/folder import, bootstrapping, and action inference.
