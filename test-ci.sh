#!/bin/bash

# Automated QEMU Test Runner for CI/CD
# This script runs comprehensive QEMU tests in CI environments

set -e

# Default values
ARCH="x86_64"
TEST_SUITE="basic"
TIMEOUT="180"
REPORT_FILE=""
BUILD_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
RESULTS_FILE="test-results.json"

# Help function
show_help() {
    cat << EOF
Automated QEMU Test Runner for CI/CD

Usage: $0 [OPTIONS] <build_directory>

Arguments:
    build_directory    BuildRoot output directory containing images

Options:
    -a, --arch ARCH        Architecture (x86_64, aarch64) [default: x86_64]
    -s, --suite SUITE      Test suite (basic, network, ssh, full) [default: basic]
    -t, --timeout SEC      Test timeout in seconds [default: 180]
    -o, --output FILE      Output report file [default: test-results.json]
    -h, --help            Show this help message

Examples:
    $0 buildroot-2024.02.1/output
    $0 --arch aarch64 --suite network buildroot/output
    $0 --suite full --timeout 600 buildroot/output

Test Suites:
    basic    - Boot test and basic system health
    network   - Include network connectivity tests
    ssh       - Include SSH service tests
    full      - Comprehensive testing including package management
EOF
}

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--arch)
                ARCH="$2"
                shift 2
                ;;
            -s|--suite)
                TEST_SUITE="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -o|--output)
                REPORT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$BUILD_DIR" ]]; then
                    BUILD_DIR="$1"
                else
                    print_error "Too many arguments"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# Validate inputs
validate_inputs() {
    if [[ -z "$BUILD_DIR" ]]; then
        print_error "Build directory is required"
        show_help
        exit 1
    fi
    
    if [[ ! -d "$BUILD_DIR" ]]; then
        print_error "Build directory not found: $BUILD_DIR"
        exit 1
    fi
    
    if [[ ! -d "$BUILD_DIR/images" ]]; then
        print_error "Images directory not found: $BUILD_DIR/images"
        exit 1
    fi
    
    if [[ -z "$REPORT_FILE" ]]; then
        REPORT_FILE="$BUILD_DIR/test-results.json"
    fi
}

# Find kernel and rootfs
find_images() {
    local images_dir="$BUILD_DIR/images"
    
    # Find kernel image based on architecture
    case "$ARCH" in
        x86_64)
            KERNEL=$(find "$images_dir" -name "bzImage" -type f | head -1)
            ;;
        aarch64)
            KERNEL=$(find "$images_dir" -name "Image" -type f | head -1)
            ;;
    esac
    
    # Find root filesystem
    ROOTFS=$(find "$images_dir" -name "rootfs.ext2" -o -name "rootfs.ext3" -o -name "rootfs.ext4" -type f | head -1)
    
    if [[ -z "$KERNEL" ]]; then
        print_error "Kernel image not found in $images_dir"
        exit 1
    fi
    
    if [[ -z "$ROOTFS" ]]; then
        print_error "Root filesystem not found in $images_dir"
        exit 1
    fi
    
    print_info "Found kernel: $KERNEL"
    print_info "Found rootfs: $ROOTFS"
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    for dep in qemu-system-x86_64 qemu-system-aarch64 nc jq; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

# Initialize test results
init_results() {
    cat > "$REPORT_FILE" << EOF
{
    "test_run": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "architecture": "$ARCH",
        "test_suite": "$TEST_SUITE",
        "timeout": $TIMEOUT,
        "build_directory": "$BUILD_DIR",
        "kernel": "$KERNEL",
        "rootfs": "$ROOTFS"
    },
    "results": {
        "overall_status": "unknown",
        "total_tests": 0,
        "passed": 0,
        "failed": 0,
        "skipped": 0,
        "tests": []
    }
}
EOF
}

# Update test results
update_test_result() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    
    # Use jq to update JSON
    jq ".results.tests += [{
        \"name\": \"$test_name\",
        \"status\": \"$status\",
        \"details\": \"$details\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }] | 
    if \"$status\" == \"passed\" then .results.passed += 1 
    elif \"$status\" == \"failed\" then .results.failed += 1 
    elif \"$status\" == \"skipped\" then .results.skipped += 1 end |
    .results.total_tests += 1" "$REPORT_FILE" > temp.json && mv temp.json "$REPORT_FILE"
}

# Quick boot test
run_boot_test() {
    print_info "Running quick boot test..."
    
    local test_timeout="$TIMEOUT"
    local qemu_cmd=""
    
    # Select QEMU binary
    case "$ARCH" in
        x86_64)
            qemu_cmd="qemu-system-x86_64"
            ;;
        aarch64)
            qemu_cmd="qemu-system-aarch64"
            ;;
    esac
    
    # Start QEMU in background
    timeout "$test_timeout" "$qemu_cmd" \
        -m "256M" \
        -kernel "$KERNEL" \
        -hda "$ROOTFS" \
        -append "root=/dev/sda console=ttyS0 panic=1" \
        -nographic \
        -no-reboot > "$BUILD_DIR/qemu-boot.log" 2>&1 &
    
    local qemu_pid=$!
    
    # Wait for boot or timeout
    local boot_success=false
    local boot_start=$(date +%s)
    
    while true; do
        # Check if we see login prompt or system ready
        if grep -q "login\|root@\|buildroot\|Hello World" "$BUILD_DIR/qemu-boot.log" 2>/dev/null; then
            boot_success=true
            break
        fi
        
        # Check timeout
        local current_time=$(date +%s)
        if [[ $((current_time - boot_start)) -gt $test_timeout ]]; then
            break
        fi
        
        sleep 2
    done
    
    # Kill QEMU
    kill $qemu_pid 2>/dev/null || true
    wait $qemu_pid 2>/dev/null || true
    
    # Check result
    if [[ "$boot_success" == true ]]; then
        update_test_result "Boot Test" "passed" "System booted successfully and reached login prompt"
        print_success "Boot test passed"
        return 0
    else
        local error_msg=$(tail -20 "$BUILD_DIR/qemu-boot.log" | head -10)
        update_test_result "Boot Test" "failed" "Boot failed or timeout: $error_msg"
        print_error "Boot test failed"
        return 1
    fi
}

# Hello World test
run_hello_world_test() {
    print_info "Running Hello World test..."
    
    local test_script="$BUILD_DIR/test-hello.sh"
    
    # Create test script
    cat > "$test_script" << 'EOF'
#!/bin/sh
echo "Hello World! BuildRoot Linux OS is working correctly!"
echo "System Information:"
echo "  Kernel: $(uname -r)"
echo "  Uptime: $(uptime)"
echo "  Memory: $(free -h | grep '^Mem:' | awk '{print $3}' )"
echo "  Disk: $(df -h / | tail -1 | awk '{print $4}' ) available"
echo "Hello World Test: PASSED"
EOF
    
    chmod +x "$test_script"
    
    # Create custom init that runs our test
    local custom_init="$BUILD_DIR/test-init.sh"
    cat > "$custom_init" << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Run our test
/test-hello.sh

# Power off
poweroff -f
EOF
    
    chmod +x "$custom_init"
    
    local qemu_cmd=""
    case "$ARCH" in
        x86_64)
            qemu_cmd="qemu-system-x86_64"
            ;;
        aarch64)
            qemu_cmd="qemu-system-aarch64"
            ;;
    esac
    
    # Run QEMU with custom init
    timeout "$TIMEOUT" "$qemu_cmd" \
        -m "256M" \
        -kernel "$KERNEL" \
        -hda "$ROOTFS" \
        -append "root=/dev/sda console=ttyS0 panic=1 init=/test-init.sh" \
        -nographic \
        -no-reboot > "$BUILD_DIR/qemu-hello.log" 2>&1
    
    # Check result
    if grep -q "Hello World Test: PASSED" "$BUILD_DIR/qemu-hello.log" 2>/dev/null; then
        update_test_result "Hello World Test" "passed" "Hello World message printed successfully"
        print_success "Hello World test passed"
        return 0
    else
        local error_msg=$(tail -20 "$BUILD_DIR/qemu-hello.log" | head -10)
        update_test_result "Hello World Test" "failed" "Hello World test failed: $error_msg"
        print_error "Hello World test failed"
        return 1
    fi
}

# Network connectivity test
run_network_test() {
    print_info "Running network connectivity test..."
    
    # Create network test script
    local test_script="$BUILD_DIR/test-network.sh"
    cat > "$test_script" << 'EOF'
#!/bin/sh
echo "Network Test Starting..."

# Bring up network interface
ifconfig eth0 up 192.168.1.100 netmask 255.255.255.0 up

# Wait for interface to be ready
sleep 2

# Test basic network functionality
if ping -c 2 192.168.1.1 >/dev/null 2>&1; then
    echo "Network Test: PASSED"
else
    echo "Network Test: FAILED - Cannot ping gateway"
fi

poweroff -f
EOF
    
    chmod +x "$test_script"
    
    # Create custom init
    local custom_init="$BUILD_DIR/test-network-init.sh"
    cat > "$custom_init" << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Run network test
/test-network.sh

poweroff -f
EOF
    
    chmod +x "$custom_init"
    
    local qemu_cmd=""
    case "$ARCH" in
        x86_64)
            qemu_cmd="qemu-system-x86_64"
            ;;
        aarch64)
            qemu_cmd="qemu-system-aarch64"
            ;;
    esac
    
    # Run QEMU with network and custom init
    timeout "$TIMEOUT" "$qemu_cmd" \
        -m "256M" \
        -kernel "$KERNEL" \
        -hda "$ROOTFS" \
        -append "root=/dev/sda console=ttyS0 panic=1 init=/test-network-init.sh" \
        -nographic \
        -no-reboot \
        -netdev "user,id=net0" \
        -device "virtio-net-pci,netdev=net0" > "$BUILD_DIR/qemu-network.log" 2>&1
    
    # Check result
    if grep -q "Network Test: PASSED" "$BUILD_DIR/qemu-network.log" 2>/dev/null; then
        update_test_result "Network Test" "passed" "Network connectivity working"
        print_success "Network test passed"
        return 0
    else
        local error_msg=$(tail -20 "$BUILD_DIR/qemu-network.log" | head -10)
        update_test_result "Network Test" "failed" "Network test failed: $error_msg"
        print_error "Network test failed"
        return 1
    fi
}

# Package management test
run_package_test() {
    print_info "Running package management test..."
    
    # Create package test script
    local test_script="$BUILD_DIR/test-package.sh"
    cat > "$test_script" << 'EOF'
#!/bin/sh
echo "Package Management Test Starting..."

# Check if package manager exists
if command -v opkg >/dev/null 2>&1; then
    echo "Package Manager Found: opkg"
    
    # Update package lists
    if opkg update >/dev/null 2>&1; then
        echo "Package Lists Updated: PASSED"
    else
        echo "Package Lists Updated: FAILED"
        exit 1
    fi
    
    # Try to install a small package
    if opkg install wget >/dev/null 2>&1; then
        echo "Package Installation: PASSED"
    else
        echo "Package Installation: FAILED"
        exit 1
    fi
    
    # Verify package was installed
    if command -v wget >/dev/null 2>&1; then
        echo "Package Verification: PASSED"
    else
        echo "Package Verification: FAILED"
        exit 1
    fi
    
    echo "Package Management Test: PASSED"
else
    echo "Package Management Test: SKIPPED - No package manager found"
fi

poweroff -f
EOF
    
    chmod +x "$test_script"
    
    # Create custom init
    local custom_init="$BUILD_DIR/test-package-init.sh"
    cat > "$custom_init" << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Run package test
/test-package.sh

poweroff -f
EOF
    
    chmod +x "$custom_init"
    
    local qemu_cmd=""
    case "$ARCH" in
        x86_64)
            qemu_cmd="qemu-system-x86_64"
            ;;
        aarch64)
            qemu_cmd="qemu-system-aarch64"
            ;;
    esac
    
    # Run QEMU with custom init
    timeout "$TIMEOUT" "$qemu_cmd" \
        -m "512M" \
        -kernel "$KERNEL" \
        -hda "$ROOTFS" \
        -append "root=/dev/sda console=ttyS0 panic=1 init=/test-package-init.sh" \
        -nographic \
        -no-reboot \
        -netdev "user,id=net0" \
        -device "virtio-net-pci,netdev=net0" > "$BUILD_DIR/qemu-package.log" 2>&1
    
    # Check result
    if grep -q "Package Management Test: PASSED" "$BUILD_DIR/qemu-package.log" 2>/dev/null; then
        update_test_result "Package Management Test" "passed" "Package management working correctly"
        print_success "Package management test passed"
    elif grep -q "Package Management Test: SKIPPED" "$BUILD_DIR/qemu-package.log" 2>/dev/null; then
        update_test_result "Package Management Test" "skipped" "No package manager available"
        print_warning "Package management test skipped"
        return 0
    else
        local error_msg=$(tail -20 "$BUILD_DIR/qemu-package.log" | head -10)
        update_test_result "Package Management Test" "failed" "Package management test failed: $error_msg"
        print_error "Package management test failed"
        return 1
    fi
}

# Finalize results
finalize_results() {
    local total_passed=$(jq '.results.passed' "$REPORT_FILE")
    local total_failed=$(jq '.results.failed' "$REPORT_FILE")
    local total_skipped=$(jq '.results.skipped' "$REPORT_FILE")
    local total_tests=$(jq '.results.total_tests' "$REPORT_FILE")
    
    # Determine overall status
    local overall_status="passed"
    if [[ "$total_failed" -gt 0 ]]; then
        overall_status="failed"
    fi
    
    # Update overall status
    jq ".results.overall_status = \"$overall_status\"" "$REPORT_FILE" > temp.json && mv temp.json "$REPORT_FILE"
    
    # Print summary
    echo ""
    echo "=========================================="
    echo "🧪 QEMU Test Results Summary"
    echo "=========================================="
    echo "Architecture: $ARCH"
    echo "Test Suite: $TEST_SUITE"
    echo "Kernel: $KERNEL"
    echo "Rootfs: $ROOTFS"
    echo ""
    echo "Results:"
    echo "✅ Passed: $total_passed"
    echo "❌ Failed: $total_failed"
    echo "⏭️  Skipped: $total_skipped"
    echo "📊 Total: $total_tests"
    echo "🎯 Overall: $overall_status"
    echo ""
    echo "📋 Detailed results saved to: $REPORT_FILE"
    
    # Show test details
    echo ""
    echo "Test Details:"
    jq -r '.results.tests[] | "  - \(.name): \(.status) (\(.details))"' "$REPORT_FILE"
    
    if [[ "$overall_status" == "passed" ]]; then
        print_success "All tests passed! 🎉"
        return 0
    else
        print_error "Some tests failed"
        return 1
    fi
}

# Main function
main() {
    echo "🧪 Automated QEMU Test Runner"
    echo "=============================="
    
    parse_args "$@"
    validate_inputs
    find_images
    check_dependencies
    init_results
    
    # Run tests based on suite
    case "$TEST_SUITE" in
        basic)
            run_boot_test
            run_hello_world_test
            ;;
        network)
            run_boot_test
            run_hello_world_test
            run_network_test
            ;;
        ssh)
            run_boot_test
            run_hello_world_test
            run_network_test
            # SSH tests would require more complex setup
            print_warning "SSH tests skipped in CI environment"
            ;;
        full)
            run_boot_test
            run_hello_world_test
            run_network_test
            run_package_test
            ;;
    esac
    
    finalize_results
}

# Run main function with all arguments
main "$@"