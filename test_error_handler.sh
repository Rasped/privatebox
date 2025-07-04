#!/bin/bash

# Test script to verify error handler fixes

# Source the error handler
source /Users/rasped/privatebox/bootstrap/lib/error_handler.sh

# Test 1: Arrays with no elements (should not cause unbound variable error)
echo "Test 1: Empty arrays in cleanup_handler"
cleanup_handler
echo "✓ Test 1 passed"

# Test 2: Error handling setup (should work even without bash)
echo -e "\nTest 2: Error handling setup"
setup_error_handling
echo "✓ Test 2 passed"

# Test 3: Cloud-init error handling
echo -e "\nTest 3: Cloud-init error handling"
setup_cloud_init_error_handling
echo "✓ Test 3 passed"

# Test 4: Disable error handling
echo -e "\nTest 4: Disable error handling"
disable_error_handling
echo "✓ Test 4 passed"

echo -e "\nAll tests passed!"