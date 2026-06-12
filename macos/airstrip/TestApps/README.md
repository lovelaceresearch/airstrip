# Airstrip Test Apps

Import these folders into Airstrip to test runtime behavior.

## hello-cli

Tests normal command actions and logs.

Actions:

- `Say Hello`
- `JSON Output`

## simple-web

Tests web server launch and the sidebar Web Servers manager.

Default port: `8765`

Expected behavior:

- Airstrip starts the server.
- Browser opens `http://localhost:8765/`.
- Sidebar shows the running server and port.
- `Open` opens the web page again.
- `Stop` stops the server.

## port-conflict-a and port-conflict-b

Tests port conflict handling.

Flow:

1. Import both folders.
2. Start `Port Conflict A`.
3. Start `Port Conflict B`.

Expected behavior:

- `Port Conflict A` uses port `9000`.
- `Port Conflict B` detects `9000` is busy and falls back to `9001` or another nearby free port.
- Sidebar shows both running servers with their actual ports.
