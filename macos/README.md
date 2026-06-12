# Airstrip

Airstrip is a macOS SwiftUI launcher for local Python and Ollama automations.

The intended user flow is:

1. Download Airstrip.
2. Drop an automation folder into the app.
3. Airstrip copies it into `~/Library/Application Support/Airstrip/Projects`.
4. The automation appears as an icon.
5. Double-click the icon to run it.

## Built-in Ollama Chat

The springboard includes an integrated "Ollama Chat" app that opens in its
own tab like any other project:

- If Ollama is installed but not running, Airstrip starts `ollama serve`
  itself (and stops it again on quit if it started it).
- Pick a model from the picker in the input bar; you can switch models
  mid-conversation and the history carries over.
- Press the + button next to the model picker to send the same prompt to
  several models at once. The tab splits into one column per model.
- The settings popover (slider icon) covers the persona (system prompt) and
  the standard Ollama generation parameters: temperature, top-p, repeat
  penalty, context window, seed, and keep-alive. "Show response stats"
  prints token counts and speed under each answer, like `ollama --verbose`.

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

- SwiftUI springboard UI
- Folder drag/drop import
- Per-project run, stop, logs, and Finder reveal
- Dependency detection for Python, Homebrew, and Ollama
- Homebrew install via visible Terminal script
- Ollama install via Homebrew when available, otherwise the official macOS download page

## Install On Another Mac

To put Airstrip plus an automation on someone else's Mac:

1. On your Mac, run `Scripts/package-app.sh`. It builds a Release app and produces `dist/Airstrip.zip`.
2. AirDrop `Airstrip.zip` and the automation folder (for example `autoc1`) to the other Mac. Airstrip skips `.airstrip-venv`, caches, and `.git` during import, so the raw folder is fine to send as-is.
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
