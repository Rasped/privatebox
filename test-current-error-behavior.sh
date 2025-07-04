#!/bin/bash
# Test script to document current error handling behavior
# This script tests each bootstrap script to understand their error handling

echo "Bootstrap Error Handling Behavior Test"
echo "====================================="
echo "Date: $(date)"
echo ""

# Create results directory
RESULTS_DIR="/tmp/error-behavior-test-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

# Function to test a script
test_script() {
    local script_name="$1"
    local script_path="$2"
    local test_args="${3:-}"
    
    echo "Testing: $script_name"
    echo "Path: $script_path"
    
    # Check if script exists
    if [[ ! -f "$script_path" ]]; then
        echo "  ERROR: Script not found"
        return
    fi
    
    # Check if script is executable
    if [[ ! -x "$script_path" ]]; then
        echo "  WARNING: Script is not executable"
    fi
    
    # Check for error handling patterns
    echo "  Error handling patterns:"
    
    # Check for set -e, -u, -o pipefail
    if grep -q "^set -e" "$script_path"; then
        echo "    ✓ Uses 'set -e'"
    fi
    if grep -q "^set -u" "$script_path"; then
        echo "    ✓ Uses 'set -u'"
    fi
    if grep -q "^set -o pipefail" "$script_path"; then
        echo "    ✓ Uses 'set -o pipefail'"
    fi
    if grep -q "^set -euo pipefail" "$script_path"; then
        echo "    ✓ Uses 'set -euo pipefail'"
    fi
    
    # Check for error handling setup
    if grep -q "setup_error_handling" "$script_path"; then
        echo "    ✓ Calls setup_error_handling()"
    fi
    
    # Check for custom error functions
    if grep -q "error_exit" "$script_path"; then
        echo "    • Has custom error_exit() function"
    fi
    if grep -q "handle_error" "$script_path"; then
        echo "    • Has custom handle_error() function"
    fi
    
    # Check for trap usage
    if grep -q "^trap " "$script_path"; then
        echo "    • Uses trap commands:"
        grep "^trap " "$script_path" | sed 's/^/      /'
    fi
    
    # Test with --help if safe
    if [[ "$script_name" == "create-ubuntu-vm.sh" ]] || [[ "$script_name" == "network-discovery.sh" ]] || [[ "$script_name" == "deploy-to-server.sh" ]]; then
        echo "  Testing with --help:"
        "$script_path" --help > "$RESULTS_DIR/${script_name}-help.out" 2>&1
        local exit_code=$?
        echo "    Exit code: $exit_code"
    fi
    
    echo ""
}

# Test bootstrap directory scripts
echo "=== Main Bootstrap Scripts ==="
test_script "bootstrap.sh" "/tmp/privatebox-bootstrap/bootstrap.sh"
test_script "deploy-to-server.sh" "/tmp/privatebox-bootstrap/deploy-to-server.sh"

echo "=== Scripts Directory ==="
for script in /tmp/privatebox-bootstrap/scripts/*.sh; do
    script_name=$(basename "$script")
    test_script "$script_name" "$script"
done

echo "=== Summary ==="
echo "Scripts with setup_error_handling():"
grep -l "setup_error_handling" /tmp/privatebox-bootstrap/*.sh /tmp/privatebox-bootstrap/scripts/*.sh 2>/dev/null | sed 's/^/  /'

echo ""
echo "Scripts without any error handling:"
for script in /tmp/privatebox-bootstrap/*.sh /tmp/privatebox-bootstrap/scripts/*.sh; do
    if ! grep -q "setup_error_handling\|set -e\|error_exit\|handle_error" "$script" 2>/dev/null; then
        echo "  $script"
    fi
done

echo ""
echo "Test results saved to: $RESULTS_DIR"
echo "Test completed at: $(date)"