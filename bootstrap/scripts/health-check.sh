#!/bin/bash
# Health check script for PrivateBox services

# Source common library
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

# Health check configuration
SERVICES=("portainer" "semaphore-ui" "semaphore-db")
PORTS=("9000" "3000" "3306")
TIMEOUT=5

# Function to check service status
check_service() {
    local service="$1"
    log_info "Checking service: $service"
    
    if systemctl is-active --quiet "$service.service"; then
        log_info "✓ $service service is active"
        return 0
    else
        log_error "✗ $service service is not active"
        return 1
    fi
}

# Function to check port availability
check_port() {
    local port="$1"
    local host="${2:-localhost}"
    
    log_info "Checking port: $host:$port"
    
    if timeout "$TIMEOUT" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        log_info "✓ Port $port is accessible"
        return 0
    else
        log_error "✗ Port $port is not accessible"
        return 1
    fi
}

# Function to check container health
check_container() {
    local container="$1"
    log_info "Checking container: $container"
    
    if podman ps --filter "name=$container" --filter "status=running" --quiet | grep -q .; then
        log_info "✓ Container $container is running"
        return 0
    else
        log_error "✗ Container $container is not running"
        return 1
    fi
}

# Function to check Semaphore API
check_semaphore_api() {
    log_info "Checking Semaphore API health"
    
    local response
    if response=$(curl -s -f --connect-timeout "$TIMEOUT" "http://localhost:3000/api/ping" 2>/dev/null); then
        log_info "✓ Semaphore API is responding"
        return 0
    else
        log_error "✗ Semaphore API is not responding"
        return 1
    fi
}

# Main health check function
perform_health_check() {
    local overall_status=0
    
    log_info "Starting PrivateBox health check..."
    log_info "================================"
    
    # Check systemd services
    log_info "Checking systemd services..."
    for service in "${SERVICES[@]}"; do
        if ! check_service "$service"; then
            overall_status=1
        fi
    done
    
    echo
    
    # Check ports
    log_info "Checking port accessibility..."
    for port in "${PORTS[@]}"; do
        if ! check_port "$port"; then
            overall_status=1
        fi
    done
    
    echo
    
    # Check containers
    log_info "Checking container status..."
    for service in "${SERVICES[@]}"; do
        if ! check_container "$service"; then
            overall_status=1
        fi
    done
    
    echo
    
    # Check Semaphore API specifically
    if ! check_semaphore_api; then
        overall_status=1
    fi
    
    echo
    log_info "================================"
    
    if [[ $overall_status -eq 0 ]]; then
        log_info "✓ All health checks passed"
        return 0
    else
        log_error "✗ Some health checks failed"
        return 1
    fi
}

# Function to show service URLs
show_service_urls() {
    local ip
    ip=$(hostname -I | awk '{print $1}')
    
    log_info "Service URLs:"
    log_info "  Portainer: http://$ip:9000"
    log_info "  Semaphore: http://$ip:3000"
}

# Function to show quick status
quick_status() {
    log_info "Quick Status Check:"
    
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service.service"; then
            echo "  $service: ✓ Running"
        else
            echo "  $service: ✗ Not running"
        fi
    done
}

# Main script logic
main() {
    case "${1:-full}" in
        "quick")
            quick_status
            ;;
        "urls")
            show_service_urls
            ;;
        "full"|"")
            perform_health_check
            echo
            show_service_urls
            ;;
        *)
            echo "Usage: $0 [quick|urls|full]"
            echo "  quick - Show quick service status"
            echo "  urls  - Show service URLs"
            echo "  full  - Full health check (default)"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi