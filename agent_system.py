#!/usr/bin/env python3
"""
SCHOFIELD QUANTUM AGENT SYSTEM
Single-file deployment
"""

import os
import requests

# Get token from environment variable
GITHUB_TOKEN = os.getenv('GITHUB_TOKEN', '')
GITHUB_USERNAME = 'schofieldquantumsolutionsinc-rgb'

class GitHubClient:
    def __init__(self):
        self.token = GITHUB_TOKEN
        self.username = GITHUB_USERNAME
        self.headers = {'Authorization': f'token {self.token}'}

    def test(self):
        r = requests.get('https://api.github.com/user', headers=self.headers)
        return r.json() if r.status_code == 200 else {'error': r.status_code}

if __name__ == '__main__':
    print("Schofield Quantum Agent System")
    print("="*40)

    if not GITHUB_TOKEN:
        print("❌ No GITHUB_TOKEN set")
        print("Run: export GITHUB_TOKEN=your_token_here")
        exit(1)

    client = GitHubClient()
    result = client.test()
    if 'login' in result:
        print(f"✅ Connected as: {result['login']}")
    else:
        print(f"❌ Failed: {result}")
