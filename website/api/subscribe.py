#!/usr/bin/env python3
"""
Newsletter subscription handler for Contextify.

Deployment: Copy to server and configure Nginx to proxy to this script.
Server location: /var/www/contextify/api/subscribe.py

Nginx config example:
    location /api/subscribe {
        proxy_pass http://127.0.0.1:8080/subscribe;
    }

Run as standalone server:
    python3 subscribe.py

Or use with CGI/WSGI as needed.
"""

import os
import re
import json
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs

# Configuration
SUBSCRIBERS_FILE = os.environ.get('SUBSCRIBERS_FILE', '/var/www/contextify/subscribers.txt')
PORT = int(os.environ.get('SUBSCRIBE_PORT', 8080))
ALLOWED_ORIGINS = ['https://contextify.sh', 'http://localhost', 'null']  # 'null' for file:// testing


def is_valid_email(email):
    """Basic email validation."""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None


def add_subscriber(email):
    """Add email to subscribers file. Returns (success, message)."""
    email = email.strip().lower()

    if not is_valid_email(email):
        return False, "Invalid email address"

    # Check for duplicates
    try:
        if os.path.exists(SUBSCRIBERS_FILE):
            with open(SUBSCRIBERS_FILE, 'r') as f:
                existing = [line.split('\t')[0] for line in f.readlines()]
                if email in existing:
                    return True, "Already subscribed"  # Don't reveal if already exists
    except Exception:
        pass  # If we can't read, continue anyway

    # Append new subscriber
    try:
        os.makedirs(os.path.dirname(SUBSCRIBERS_FILE), exist_ok=True)
        with open(SUBSCRIBERS_FILE, 'a') as f:
            timestamp = datetime.utcnow().isoformat() + 'Z'
            f.write(f"{email}\t{timestamp}\n")
        return True, "Subscribed successfully"
    except Exception as e:
        return False, f"Server error: {str(e)}"


class SubscribeHandler(BaseHTTPRequestHandler):
    def _send_response(self, status, data, origin=None):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        if origin and origin in ALLOWED_ORIGINS:
            self.send_header('Access-Control-Allow-Origin', origin)
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        origin = self.headers.get('Origin', '')
        self._send_response(200, {}, origin)

    def do_POST(self):
        """Handle subscription request."""
        origin = self.headers.get('Origin', '')

        # Read POST data
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')

        # Parse form data or JSON
        email = None
        content_type = self.headers.get('Content-Type', '')

        if 'application/json' in content_type:
            try:
                data = json.loads(post_data)
                email = data.get('email', '')
            except json.JSONDecodeError:
                self._send_response(400, {'success': False, 'message': 'Invalid JSON'}, origin)
                return
        else:
            # Form data
            params = parse_qs(post_data)
            email = params.get('email', [''])[0]

        if not email:
            self._send_response(400, {'success': False, 'message': 'Email required'}, origin)
            return

        success, message = add_subscriber(email)
        status = 200 if success else 400
        self._send_response(status, {'success': success, 'message': message}, origin)

    def log_message(self, format, *args):
        """Custom logging."""
        print(f"[{datetime.now().isoformat()}] {args[0]}")


def main():
    """Run the subscription server."""
    server = HTTPServer(('127.0.0.1', PORT), SubscribeHandler)
    print(f"Subscribe server running on port {PORT}")
    print(f"Subscribers file: {SUBSCRIBERS_FILE}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down")
        server.shutdown()


if __name__ == '__main__':
    main()
