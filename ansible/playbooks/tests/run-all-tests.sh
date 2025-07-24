#!/bin/bash
#
# PrivateBox Test Suite Runner
# Executes all test playbooks and generates a comprehensive report
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="/tmp/privatebox-test-reports-${TIMESTAMP}"
SUMMARY_FILE="${REPORT_DIR}/test-summary.txt"

# Test playbooks to run
TEST_PLAYBOOKS=(
    "test-network-discovery.yml"
    "test-ansible-infrastructure.yml"
    "test-vm-creation.yml"
    "test-utility-components.yml"
    "test-integration.yml"
)

# Initialize test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

create_report_directory() {
    print_header "Creating Report Directory"
    mkdir -p "$REPORT_DIR"
    print_success "Created report directory: $REPORT_DIR"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check for ansible-playbook
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "ansible-playbook not found. Please install Ansible."
        exit 1
    fi
    print_success "ansible-playbook found"
    
    # Check for required Python modules
    if ! python3 -c "import yaml" &> /dev/null; then
        print_warning "Python YAML module not found. Some features may not work."
    fi
    
    # Check if running with appropriate permissions
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Some tests may behave differently."
    fi
    
    # Verify test playbooks exist
    local missing_playbooks=()
    for playbook in "${TEST_PLAYBOOKS[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$playbook" ]]; then
            missing_playbooks+=("$playbook")
        fi
    done
    
    if [[ ${#missing_playbooks[@]} -gt 0 ]]; then
        print_error "Missing test playbooks: ${missing_playbooks[*]}"
        exit 1
    fi
    print_success "All test playbooks found"
}

run_test_playbook() {
    local playbook=$1
    local test_name=$(basename "$playbook" .yml)
    local log_file="${REPORT_DIR}/${test_name}.log"
    local result_file="${REPORT_DIR}/${test_name}.json"
    
    print_header "Running Test: $test_name"
    
    # Run the playbook
    if ansible-playbook \
        -i localhost, \
        -c local \
        "$SCRIPT_DIR/$playbook" \
        -e "ansible_python_interpreter=/usr/bin/python3" \
        > "$log_file" 2>&1; then
        
        print_success "Test completed: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        
        # Extract test results from log if possible
        if grep -q "Total Tests:" "$log_file"; then
            local test_count=$(grep "Total Tests:" "$log_file" | tail -1 | awk '{print $3}')
            local passed=$(grep "Passed:" "$log_file" | tail -1 | awk '{print $2}')
            local failed=$(grep "Failed:" "$log_file" | tail -1 | awk '{print $2}')
            
            echo "Test: $test_name" >> "$SUMMARY_FILE"
            echo "  Total: $test_count" >> "$SUMMARY_FILE"
            echo "  Passed: $passed" >> "$SUMMARY_FILE"
            echo "  Failed: $failed" >> "$SUMMARY_FILE"
            echo "" >> "$SUMMARY_FILE"
            
            TOTAL_TESTS=$((TOTAL_TESTS + test_count))
        fi
    else
        print_error "Test failed: $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        
        # Show last few lines of error
        echo "Error output:" >> "$SUMMARY_FILE"
        tail -20 "$log_file" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
    fi
    
    # Show test output location
    echo "  Log file: $log_file"
}

run_all_tests() {
    print_header "Running All Tests"
    
    # Initialize summary file
    echo "PrivateBox Test Suite Results" > "$SUMMARY_FILE"
    echo "Generated: $(date)" >> "$SUMMARY_FILE"
    echo "================================" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    # Run each test playbook
    for playbook in "${TEST_PLAYBOOKS[@]}"; do
        run_test_playbook "$playbook"
    done
}

generate_final_report() {
    print_header "Test Suite Summary"
    
    # Calculate pass rate
    local total_suites=$((PASSED_TESTS + FAILED_TESTS + SKIPPED_TESTS))
    local pass_rate=0
    if [[ $total_suites -gt 0 ]]; then
        pass_rate=$(( (PASSED_TESTS * 100) / total_suites ))
    fi
    
    # Add summary to report
    {
        echo ""
        echo "================================"
        echo "FINAL SUMMARY"
        echo "================================"
        echo "Test Suites Run: $total_suites"
        echo "Passed: $PASSED_TESTS"
        echo "Failed: $FAILED_TESTS"
        echo "Skipped: $SKIPPED_TESTS"
        echo "Pass Rate: ${pass_rate}%"
        echo ""
        echo "Individual Tests: $TOTAL_TESTS"
    } >> "$SUMMARY_FILE"
    
    # Display summary
    cat "$SUMMARY_FILE"
    
    # Create HTML report if possible
    if command -v python3 &> /dev/null; then
        create_html_report
    fi
}

create_html_report() {
    local html_file="${REPORT_DIR}/test-report.html"
    
    cat > "$html_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>PrivateBox Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .summary { background: #f0f0f0; padding: 15px; border-radius: 5px; }
        .passed { color: green; }
        .failed { color: red; }
        .warning { color: orange; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .test-log { background: #f9f9f9; padding: 10px; margin: 10px 0; 
                    border-left: 3px solid #4CAF50; font-family: monospace; }
    </style>
</head>
<body>
    <h1>PrivateBox Test Suite Report</h1>
EOF
    
    # Add timestamp
    echo "<p>Generated: $(date)</p>" >> "$html_file"
    
    # Add summary
    {
        echo "<div class='summary'>"
        echo "<h2>Summary</h2>"
        echo "<p>Test Suites Run: $((PASSED_TESTS + FAILED_TESTS))</p>"
        echo "<p class='passed'>Passed: $PASSED_TESTS</p>"
        echo "<p class='failed'>Failed: $FAILED_TESTS</p>"
        echo "</div>"
    } >> "$html_file"
    
    # Add test details
    echo "<h2>Test Details</h2>" >> "$html_file"
    echo "<table>" >> "$html_file"
    echo "<tr><th>Test Suite</th><th>Status</th><th>Log File</th></tr>" >> "$html_file"
    
    for playbook in "${TEST_PLAYBOOKS[@]}"; do
        local test_name=$(basename "$playbook" .yml)
        local log_file="${test_name}.log"
        
        if [[ -f "${REPORT_DIR}/${log_file}" ]]; then
            if grep -q "failed=0" "${REPORT_DIR}/${log_file}"; then
                echo "<tr><td>$test_name</td><td class='passed'>PASSED</td><td><a href='${log_file}'>View Log</a></td></tr>" >> "$html_file"
            else
                echo "<tr><td>$test_name</td><td class='failed'>FAILED</td><td><a href='${log_file}'>View Log</a></td></tr>" >> "$html_file"
            fi
        fi
    done
    
    echo "</table>" >> "$html_file"
    echo "</body></html>" >> "$html_file"
    
    print_success "HTML report created: $html_file"
}

cleanup_old_reports() {
    print_header "Cleaning Up Old Reports"
    
    # Keep only the last 5 test reports
    local report_count=$(find /tmp -maxdepth 1 -name "privatebox-test-reports-*" -type d | wc -l)
    
    if [[ $report_count -gt 5 ]]; then
        find /tmp -maxdepth 1 -name "privatebox-test-reports-*" -type d | 
        sort | head -n -5 | xargs rm -rf
        print_success "Cleaned up old test reports"
    fi
}

# Main execution
main() {
    echo "PrivateBox Test Suite Runner"
    echo "============================"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                # Run only critical tests
                TEST_PLAYBOOKS=(
                    "test-network-discovery.yml"
                    "test-ansible-infrastructure.yml"
                )
                print_warning "Running in quick mode (limited tests)"
                ;;
            --test)
                # Run specific test
                if [[ -n "${2:-}" ]]; then
                    TEST_PLAYBOOKS=("$2")
                    shift
                else
                    print_error "Please specify a test playbook"
                    exit 1
                fi
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --quick       Run only critical tests"
                echo "  --test FILE   Run specific test playbook"
                echo "  --help        Show this help message"
                echo ""
                echo "Available tests:"
                for test in "${TEST_PLAYBOOKS[@]}"; do
                    echo "  - $test"
                done
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
    
    # Run test suite
    create_report_directory
    check_prerequisites
    run_all_tests
    generate_final_report
    cleanup_old_reports
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        print_error "Test suite completed with failures"
        exit 1
    else
        print_success "All tests passed!"
        exit 0
    fi
}

# Run main function
main "$@"