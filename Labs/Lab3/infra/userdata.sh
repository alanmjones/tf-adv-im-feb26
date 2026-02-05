#!/bin/bash
yum update -y
yum install -y python3

cat <<EOF > /home/ec2-user/app.py
from http.server import BaseHTTPRequestHandler, HTTPServer

API_KEY = "${api_key}"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"Loaded API Key: {API_KEY}".encode())

HTTPServer(("", 80), Handler).serve_forever()
EOF

python3 /home/ec2-user/app.py &