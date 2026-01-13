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
import fcntl
import time
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs
from collections import defaultdict

# Configuration
SUBSCRIBERS_FILE = os.environ.get('SUBSCRIBERS_FILE', '/var/www/contextify/subscribers.txt')
PORT = int(os.environ.get('SUBSCRIBE_PORT', 8080))
ALLOWED_ORIGINS = ['https://contextify.sh', 'http://localhost', 'null']  # 'null' for file:// testing

# Security limits
MAX_EMAIL_LENGTH = 254
MAX_PAYLOAD_SIZE = 1024
MAX_REQUESTS_PER_MINUTE = 5

# Rate limiting (in-memory, resets on restart)
request_log = defaultdict(list)  # IP -> [timestamps]


def check_rate_limit(ip):
    """Returns True if request is allowed, False if rate limited."""
    now = time.time()
    minute_ago = now - 60

    # Clean old entries
    request_log[ip] = [t for t in request_log[ip] if t > minute_ago]

    if len(request_log[ip]) >= MAX_REQUESTS_PER_MINUTE:
        return False

    request_log[ip].append(now)
    return True


def is_valid_email(email):
    """Basic email validation."""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None


def add_subscriber(email):
    """Add email to subscribers file. Returns (success, message)."""
    email = email.strip().lower()

    # Length check
    if len(email) > MAX_EMAIL_LENGTH:
        return False, "Invalid email address"

    if not is_valid_email(email):
        return False, "Invalid email address"

    # Ensure directory exists
    os.makedirs(os.path.dirname(SUBSCRIBERS_FILE), exist_ok=True)

    # Use file locking for safe concurrent access
    try:
        with open(SUBSCRIBERS_FILE, 'a+') as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                # Check for duplicates
                f.seek(0)
                existing = [line.split('\t')[0] for line in f.readlines()]
                if email in existing:
                    return True, "Thanks for subscribing!"  # Same message, no enumeration

                # Append new subscriber
                timestamp = datetime.utcnow().isoformat() + 'Z'
                f.write(f"{email}\t{timestamp}\n")
                return True, "Thanks for subscribing!"
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except Exception as e:
        return False, "Server error"  # Don't leak details


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
        client_ip = self.client_address[0]

        # Rate limiting
        if not check_rate_limit(client_ip):
            self._send_response(429, {'success': False, 'message': 'Too many requests. Try again later.'}, origin)
            return

        # Payload size limit
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length > MAX_PAYLOAD_SIZE:
            self._send_response(413, {'success': False, 'message': 'Request too large'}, origin)
            return

        # Read POST data
        post_data = self.rfile.read(content_length).decode('utf-8')

        # Parse form data or JSON
        email = None
        honeypot = None
        content_type = self.headers.get('Content-Type', '')

        if 'application/json' in content_type:
            try:
                data = json.loads(post_data)
                email = data.get('email', '')
                honeypot = data.get('website', '')  # Honeypot field
            except json.JSONDecodeError:
                self._send_response(400, {'success': False, 'message': 'Invalid request'}, origin)
                return
        else:
            # Form data
            params = parse_qs(post_data)
            email = params.get('email', [''])[0]
            honeypot = params.get('website', [''])[0]

        # Honeypot check - bots fill this in, humans don't see it
        if honeypot:
            # Pretend success but don't save
            self._send_response(200, {'success': True, 'message': 'Thanks for subscribing!'}, origin)
            return

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
