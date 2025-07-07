#!/bin/bash
# Test setup script to verify file copying works

echo "==================================="
echo "Test Setup Script Running"
echo "==================================="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "User: $(whoami)"
echo "==================================="

# Create a test file to verify script ran
echo "Script executed at $(date)" > /tmp/test-setup-completed.txt

echo "Test setup completed successfully!"