#!/bin/bash

# =====================================================================================
# Mycelium-Matrix Chat - Validation Library
# =====================================================================================
# This library provides comprehensive validation functions for deployment testing

# =====================================================================================
# Health Check Functions
# =====================================================================================

check_service_health() {
    local url="$1"
    local timeout="${2:-30}"
    local expected_status="${3:-200}"

    debug "Checking service health: $url (timeout: ${timeout}s)"

    local response
    if ! response=$(curl -s -w "%{http_code}" -o /dev/null --max-time "$timeout" "$url" 2>/dev/null); then
        debug "Service health check failed: $url"
        return 1
    fi

    if [ "$response" = "$expected_status" ]; then
        debug "Service health check passed: $url (status: $response)"
        return 0
    else
        debug "Service health check failed: $url (expected: $expected_status, got: $response)"
        return 1
    fi
}

check_port_open() {
    local host="$1"
    local port="$2"
    local timeout="${3:-10}"

    debug "Checking if port $port is open on $host"

    if timeout "$timeout" nc -z "$host" "$port" 2>/dev/null; then
        debug "Port $port is open on $host"
        return 0
    else
        debug "Port $port is not accessible on $host"
        return 1
    fi
}

# =====================================================================================
# Application-Specific Validation Functions
# =====================================================================================

validate_matrix_bridge() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Validating Matrix Bridge..."

    local bridge_port
    bridge_port=$(get_config "deployment.bridge_port" "8081")

    # Check if bridge port is open
    if ! execute_remote "$ip" "$user" "netstat -tuln | grep :$bridge_port"; then
        error "Matrix Bridge port $bridge_port is not listening"
        return 1
    fi

    # Check bridge health endpoint
    local bridge_url="http://localhost:$bridge_port/health"
    if ! execute_remote "$ip" "$user" "curl -s '$bridge_url' | grep -q 'OK\|healthy\|running'"; then
        error "Matrix Bridge health check failed"
        return 1
    fi

    success "Matrix Bridge validation passed"
}

validate_web_gateway() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Validating Web Gateway..."

    local gateway_port
    gateway_port=$(get_config "deployment.gateway_port" "8080")

    # Check if gateway port is open
    if ! execute_remote "$ip" "$user" "netstat -tuln | grep :$gateway_port"; then
        error "Web Gateway port $gateway_port is not listening"
        return 1
    fi

    # Check gateway health
    local gateway_url="http://localhost:$gateway_port/api/health"
    if ! execute_remote "$ip" "$user" "curl -s '$gateway_url' | grep -q 'OK\|healthy\|running'"; then
        error "Web Gateway health check failed"
        return 1
    fi

    success "Web Gateway validation passed"
}

validate_frontend() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Validating Frontend..."

    local frontend_port
    frontend_port=$(get_config "deployment.frontend_port" "5173")

    # Check if frontend port is open
    if ! execute_remote "$ip" "$user" "netstat -tuln | grep :$frontend_port"; then
        error "Frontend port $frontend_port is not listening"
        return 1
    fi

    # Check if frontend serves HTML
    local frontend_url="http://localhost:$frontend_port"
    if ! execute_remote "$ip" "$user" "curl -s '$frontend_url' | grep -q '<!DOCTYPE html>\|<html>'"; then
        error "Frontend is not serving HTML content"
        return 1
    fi

    success "Frontend validation passed"
}

validate_mycelium() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Validating Mycelium..."

    # Check if mycelium command exists
    if ! execute_remote "$ip" "$user" "command -v mycelium"; then
        error "Mycelium command not found"
        return 1
    fi

    # Check mycelium service status
    if ! execute_remote "$ip" "$user" "systemctl is-active --quiet myceliumd"; then
        warning "Mycelium service is not running"
        # Try to start it
        if execute_remote "$ip" "$user" "sudo systemctl start myceliumd"; then
            debug "Mycelium service started successfully"
        else
            error "Failed to start Mycelium service"
            return 1
        fi
    fi

    # Check mycelium connectivity (if enabled)
    local check_mycelium
    check_mycelium=$(get_config "validation.check_mycelium_connectivity" "true")

    if [ "$check_mycelium" = "true" ]; then
        if ! execute_remote "$ip" "$user" "mycelium status 2>/dev/null | grep -q 'connected\|running'"; then
            warning "Mycelium is not connected to peers"
            # This is not a fatal error, just a warning
        else
            debug "Mycelium is connected"
        fi
    fi

    success "Mycelium validation passed"
}

validate_database() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Validating Database..."

    # Check if PostgreSQL is running
    if ! execute_remote "$ip" "$user" "pg_isready -h localhost -U $(get_config 'database.user' 'mycelium_user')"; then
        error "PostgreSQL is not accessible"
        return 1
    fi

    # Check if database exists
    local db_name
    db_name=$(get_config "database.name" "mycelium_matrix")

    if ! execute_remote "$ip" "$user" "psql -h localhost -U $(get_config 'database.user' 'mycelium_user') -l | grep -q '$db_name'"; then
        error "Database $db_name does not exist"
        return 1
    fi

    success "Database validation passed"
}

# =====================================================================================
# System Validation Functions
# =====================================================================================

validate_system_resources() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Validating System Resources..."

    # Check CPU cores
    local required_cpu
    required_cpu=$(get_config "vm.cpu" "2")

    local actual_cpu
    actual_cpu=$(execute_remote "$ip" "$user" "nproc" 2>/dev/null || echo "1")

    if [ "$actual_cpu" -lt "$required_cpu" ]; then
        warning "CPU cores: $actual_cpu (required: $required_cpu)"
    else
        debug "CPU cores: $actual_cpu ✓"
    fi

    # Check memory
    local required_memory
    required_memory=$(get_config "vm.memory" "4")

    local actual_memory
    actual_memory=$(execute_remote "$ip" "$user" "free -g | awk 'NR==2{printf \"%.0f\", \$2}'" 2>/dev/null || echo "4")

    if [ "$actual_memory" -lt "$required_memory" ]; then
        warning "Memory: ${actual_memory}GB (required: ${required_memory}GB)"
    else
        debug "Memory: ${actual_memory}GB ✓"
    fi

    # Check disk space
    local required_disk
    required_disk=$(get_config "vm.disk" "50")

    local actual_disk
    actual_disk=$(execute_remote "$ip" "$user" "df -BG / | awk 'NR==2{printf \"%.0f\", \$2}'" 2>/dev/null || echo "50")

    if [ "$actual_disk" -lt "$required_disk" ]; then
        warning "Disk space: ${actual_disk}GB (required: ${required_disk}GB)"
    else
        debug "Disk space: ${actual_disk}GB ✓"
    fi

    success "System resources validation completed"
}

validate_network_connectivity() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Validating Network Connectivity..."

    # Test basic connectivity
    if ! execute_remote "$ip" "$user" "ping -c 1 8.8.8.8"; then
        error "No internet connectivity"
        return 1
    fi

    # Test DNS resolution
    if ! execute_remote "$ip" "$user" "nslookup github.com"; then
        error "DNS resolution failed"
        return 1
    fi

    success "Network connectivity validation passed"
}

# =====================================================================================
# Integration Test Functions
# =====================================================================================

test_matrix_federation() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Testing Matrix Federation..."

    local bridge_port
    bridge_port=$(get_config "deployment.bridge_port" "8081")

    # Test federation endpoint
    local federation_url="http://localhost:$bridge_port/_matrix/federation/v1/version"
    if ! execute_remote "$ip" "$user" "curl -s '$federation_url' | grep -q 'server'"; then
        error "Matrix federation endpoint not responding"
        return 1
    fi

    success "Matrix federation test passed"
}

test_api_endpoints() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Testing API Endpoints..."

    local api_endpoints
    api_endpoints=$(get_config "validation.api_endpoints")

    IFS=',' read -ra ENDPOINTS <<< "$api_endpoints"
    for endpoint in "${ENDPOINTS[@]}"; do
        endpoint=$(trim "$endpoint")

        if ! execute_remote "$ip" "$user" "curl -s '$endpoint' | grep -q 'OK\|success\|200'"; then
            error "API endpoint failed: $endpoint"
            return 1
        fi
    done

    success "API endpoints test passed"
}

# =====================================================================================
# Performance Test Functions
# =====================================================================================

run_performance_tests() {
    local ip="$1"
    local user="${2:-muser}"

    log "🔍 Running Performance Tests..."

    local test_duration
    test_duration=$(get_config "validation.performance_test_duration" "30")

    # Test response times
    local gateway_url="http://localhost:$(get_config 'deployment.gateway_port' '8080')/api/health"
    local total_time=0
    local requests=10

    for ((i = 1; i <= requests; i++)); do
        local response_time
        response_time=$(execute_remote "$ip" "$user" "curl -s -w '%{time_total}' -o /dev/null '$gateway_url'" 2>/dev/null || echo "0")
        total_time=$(echo "$total_time + $response_time" | bc -l 2>/dev/null || echo "$total_time")
    done

    local avg_response_time
    avg_response_time=$(echo "scale=3; $total_time / $requests" | bc -l 2>/dev/null || echo "0")

    if (( $(echo "$avg_response_time > 1.0" | bc -l 2>/dev/null || echo "0") )); then
        warning "Average response time: ${avg_response_time}s (should be < 1.0s)"
    else
        debug "Average response time: ${avg_response_time}s ✓"
    fi

    success "Performance tests completed"
}

# =====================================================================================
# Comprehensive Validation Pipeline
# =====================================================================================

run_full_validation() {
    local ip="$1"
    local environment="${2:-tfgrid}"

    log "🚀 Starting comprehensive validation suite..."

    local errors=0
    local start_time
    start_time=$(date +%s)

    # System validation
    if ! validate_system_resources "$ip"; then
        ((errors++))
    fi

    if ! validate_network_connectivity "$ip"; then
        ((errors++))
    fi

    # Service validation
    if ! validate_mycelium "$ip"; then
        ((errors++))
    fi

    if ! validate_database "$ip"; then
        ((errors++))
    fi

    if ! validate_matrix_bridge "$ip"; then
        ((errors++))
    fi

    if ! validate_web_gateway "$ip"; then
        ((errors++))
    fi

    if ! validate_frontend "$ip"; then
        ((errors++))
    fi

    # Integration tests
    if ! test_api_endpoints "$ip"; then
        ((errors++))
    fi

    if ! test_matrix_federation "$ip"; then
        ((errors++))
    fi

    # Performance tests
    if ! run_performance_tests "$ip"; then
        ((errors++))
    fi

    local duration=$(( $(date +%s) - start_time ))

    if [ $errors -eq 0 ]; then
        success "✅ All validations passed (${duration}s)"
        return 0
    else
        error "❌ $errors validation(s) failed (${duration}s)"
        return 1
    fi
}

# =====================================================================================
# Local Validation Functions
# =====================================================================================

validate_local_deployment() {
    log "🔍 Validating local deployment..."

    local errors=0

    # Check Docker services
    if ! docker ps | grep -q mycelium-matrix; then
        error "No Mycelium-Matrix containers running"
        ((errors++))
    fi

    # Check local ports
    local ports=("8080" "8081" "5173")
    for port in "${ports[@]}"; do
        if ! check_port_open "localhost" "$port"; then
            error "Port $port is not accessible locally"
            ((errors++))
        fi
    done

    # Check local services
    if ! check_service_health "http://localhost:8080/api/health"; then
        error "Local API health check failed"
        ((errors++))
    fi

    if ! check_service_health "http://localhost:5173"; then
        error "Local frontend health check failed"
        ((errors++))
    fi

    if [ $errors -eq 0 ]; then
        success "Local deployment validation passed"
        return 0
    else
        error "$errors local validation(s) failed"
        return 1
    fi
}

# =====================================================================================
# Reporting Functions
# =====================================================================================

generate_validation_report() {
    local ip="$1"
    local environment="$2"
    local report_file="${3:-/tmp/validation-report-$(date +%Y%m%d-%H%M%S).txt}"

    log "Generating validation report: $report_file"

    {
        echo "Mycelium-Matrix Chat - Validation Report"
        echo "========================================"
        echo "Date: $(date)"
        echo "Environment: $environment"
        echo "Target IP: $ip"
        echo ""
        echo "Configuration Summary:"
        echo "----------------------"
        show_config_summary
        echo ""
        echo "Validation Results:"
        echo "-------------------"
        echo "✅ System Resources: $(validate_system_resources "$ip" 2>/dev/null && echo "PASS" || echo "FAIL")"
        echo "✅ Network Connectivity: $(validate_network_connectivity "$ip" 2>/dev/null && echo "PASS" || echo "FAIL")"
        echo "✅ Mycelium: $(validate_mycelium "$ip" 2>/dev/null && echo "PASS" || echo "FAIL")"
        echo "✅ Database: $(validate_database "$ip" 2>/dev/null && echo "PASS" || echo "FAIL")"
        echo "✅ Matrix Bridge: $(validate_matrix_bridge "$ip" 2>/dev/null && echo "PASS" || echo "FAIL")"
        echo "✅ Web Gateway: $(validate_web_gateway "$ip" 2>/dev/null && echo "PASS" || echo "FAIL")"
        echo "✅ Frontend: $(validate_frontend "$ip" 2>/dev/null && echo "PASS" || echo "FAIL")"
        echo "✅ API Endpoints: $(test_api_endpoints "$ip" 2>/dev/null && echo "PASS" || echo "FAIL")"
        echo "✅ Matrix Federation: $(test_matrix_federation "$ip" 2>/dev/null && echo "PASS" || echo "FAIL")"
        echo ""
        echo "Performance Metrics:"
        echo "--------------------"
        # Add performance metrics here
        echo ""
        echo "Recommendations:"
        echo "----------------"
        # Add recommendations based on validation results
        echo ""
    } > "$report_file"

    success "Validation report generated: $report_file"
}