# Airstrip Manifest Authoring Prompt

Use this prompt with a coding agent inside any local automation repository.

## Prompt

You are preparing this repository to run inside Airstrip, a macOS launcher for local automation projects.

Your task is to inspect the repository and create an `airstrip.json` file at the repository root. Do not change application code unless the project cannot be launched without a tiny compatibility wrapper. Prefer adding only `airstrip.json`.

Airstrip imports a copy of the folder, creates a project-local `.airstrip-venv` for Python actions, installs dependencies when `requirements` is set, optionally pulls Ollama models, and runs named actions from the project root.

## What To Inspect

Read these files when present:

- `README.md`
- `pyproject.toml`
- `requirements.txt`
- `setup.py`
- `package.json`
- `Makefile`
- shell scripts such as `run.sh`, `start.sh`, or `test.sh`
- Python entry points such as `main.py`, `app.py`, `streamlit_app.py`, `app/main.py`, or CLI modules
- sample data folders such as `examples`, `samples`, `test info`, `fixtures`, or `data`

Find the commands a normal non-technical user should be able to run. Prefer commands documented in the README over guessed commands.

## Output File

Create this file:

```text
airstrip.json
```

Use this schema:

```json
{
  "name": "Human Friendly Project Name",
  "icon": "icon.png",
  "run": "python app.py",
  "actions": [
    {
      "name": "Run",
      "command": "python app.py",
      "isDefault": true
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

## Field Rules

- `name`: Required in practice. Use a short user-facing name, not a package slug.
- `icon`: Optional. Include only if the file already exists.
- `run`: Optional when `actions` exists. Use it for the single best default command.
- `actions`: Preferred when the project has more than one useful command.
- `requirements`: Include when `requirements.txt` exists and should be installed with pip.
- `tools`: Include when the project shells out to command-line tools that are not part of macOS (for example `pdftoppm`, `ffmpeg`, `tesseract`). Each entry has `command` (the binary name the code invokes) and `brew` (the Homebrew package that provides it). Airstrip checks for these before running and offers a one-click install. Search the code for `subprocess`, `shutil.which`, or `Process` calls to find them.
- `ollama.models`: Include only when the project clearly requires local Ollama models.

## Action Rules

Each action must have:

- `name`: Short button label, 1-4 words.
- `command`: Shell command run from the project root after dependencies are installed.
- `isDefault`: Set `true` on exactly one action, normally the safest demo or primary workflow.

Good action names:

- `Run Demo`
- `Start UI`
- `Compare Email`
- `Extract PDF`
- `Export JSON`
- `Process Folder`
- `Open Dashboard`

Avoid action names like:

- `Command 1`
- `Run script`
- `Do thing`
- `Test`, unless it truly runs tests

## Command Rules

Airstrip runs commands from the project root using `zsh`.

Prefer:

```sh
python -m app.main
python app.py
streamlit run streamlit_app.py
python -m package.cli
```

Do not use:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Airstrip handles venv creation and dependency installation when `requirements` is set.

Prefer `python` in manifest commands, not `python3`. Airstrip creates and activates a venv using global `python3`, then runs the action inside that venv where `python` is available.

If paths contain spaces, quote them:

```json
{
  "name": "Compare Email",
  "command": "python -m app.main \"test info/sample.pdf\" --email \"test info/email.txt\""
}
```

## User Input UX

Current Airstrip actions are fixed commands. If the project needs user-selected files, create one safe demo action using bundled sample files and add planned input metadata in an `x-airstrip-notes` field.

Example:

```json
{
  "name": "Freight Checker",
  "requirements": "requirements.txt",
  "actions": [
    {
      "name": "Compare Sample",
      "command": "python -m app.main \"test info/S609997567_20260605052025.pdf\" --email \"test info/email.txt\"",
      "isDefault": true
    }
  ],
  "x-airstrip-notes": {
    "needsInputs": [
      {
        "name": "pdf",
        "type": "file",
        "extensions": ["pdf"]
      },
      {
        "name": "email",
        "type": "file",
        "extensions": ["txt"]
      }
    ]
  }
}
```

Do not invent an input schema as if Airstrip supports it today. Use `x-airstrip-notes` for future UX hints only.

## UI Projects

If the project starts a local web UI, make the action command start the server. Examples:

```json
{
  "name": "Start UI",
  "command": "streamlit run streamlit_app.py --server.port $PORT",
  "isDefault": true,
  "web": {
    "port": 8501,
    "openPath": "/",
    "openOnStart": true,
    "allowPortFallback": true
  }
}
```

```json
{
  "name": "Start Dashboard",
  "command": "uvicorn app.web:app --host 127.0.0.1 --port {PORT}",
  "web": {
    "port": 8000,
    "openPath": "/"
  }
}
```

If the project starts a local web server, include a `web` block. Airstrip checks whether the port is available, can fall back to the next available port, sets `PORT` and `AIRSTRIP_PORT`, replaces `{PORT}` inside the command string, opens the URL, and stops the selected port when the user stops the project.

Use `$PORT` for tools that read environment variables. Use `{PORT}` for tools that need a literal number in the command.

## Final Checklist

Before finishing:

- Confirm every command works from the repository root.
- Confirm exactly one action has `"isDefault": true`.
- Confirm `requirements` points to an existing file or is omitted.
- Confirm listed Ollama models are actually needed.
- Confirm paths with spaces are quoted.
- Keep the manifest valid JSON.

## Example For A CLI With Sample Files

```json
{
  "name": "Freight Checker",
  "requirements": "requirements.txt",
  "actions": [
    {
      "name": "Extract PDF",
      "command": "python -m app.main \"test info/S609997567_20260605052025.pdf\"",
      "isDefault": true
    },
    {
      "name": "Compare Email",
      "command": "python -m app.main \"test info/S609997567_20260605052025.pdf\" --email \"test info/email.txt\""
    },
    {
      "name": "Export JSON",
      "command": "python -m app.main \"test info/S609997567_20260605052025.pdf\" --email \"test info/email.txt\" --json"
    }
  ]
}
```
