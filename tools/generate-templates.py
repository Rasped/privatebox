#!/usr/bin/env python3
"""
Semaphore template generation script.
This will eventually parse Ansible playbooks and create Semaphore templates.
"""
import os
import sys

def main():
    print("=== Semaphore Template Generator ===")
    print(f"Python version: {sys.version}")
    print(f"Current working directory: {os.getcwd()}")
    print(f"Script location: {os.path.abspath(__file__)}")
    print(f"Repository root check: {os.path.exists('ansible/playbooks')}")
    print("\nEnvironment variables:")
    for key, value in sorted(os.environ.items()):
        if key.startswith(('SEMAPHORE', 'ANSIBLE', 'PWD', 'PATH', 'USER')):
            print(f"  {key}: {value}")

if __name__ == "__main__":
    main()