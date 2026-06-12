import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PORT = int(os.environ.get("PORT", "8765"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Simple Web</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      margin: 48px;
      color: #17212b;
      background: #f6f8fa;
    }}
    main {{
      max-width: 680px;
      padding: 28px;
      border: 1px solid #d0d7de;
      border-radius: 8px;
      background: white;
    }}
    code {{
      padding: 2px 6px;
      background: #edf2f7;
      border-radius: 4px;
    }}
  </style>
</head>
<body>
  <main>
    <h1>Simple Web</h1>
    <p>This local web server is running under Airstrip.</p>
    <p>Port: <code>{PORT}</code></p>
    <p>Path: <code>{self.path}</code></p>
  </main>
</body>
</html>
"""
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    print(f"Serving Simple Web on http://localhost:{PORT}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
