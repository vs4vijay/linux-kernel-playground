#!/bin/bash

# QEMU Test Script for BuildRoot Linux OS
# This script boots the system and runs comprehensive tests

set -e

# Default values
ARCH="x86_64"
KERNEL=""
ROOTFS=""
MEMORY="512M"
TIMEOUT="300"
VERBOSE=false
TEST_TYPE="basic"
SERIAL_PORT="5555"
SSH_PORT="2222"
NETWORKING="user"
KVM=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Temporary files
TEMP_DIR=$(mktemp -d)
SSH_CONFIG="$TEMP_DIR/ssh_config"
SERIAL_LOG="$TEMP_DIR/serial.log"

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up..."
    if [[ -n "$QEMU_PID" ]]; then
        kill $QEMU_PID 2>/dev/null || true
        wait $QEMU_PID 2>/dev/null || true
    fi
    rm -rf "$TEMP_DIR"
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Help function
show_help() {
    cat << EOF
QEMU Test Script for BuildRoot Linux OS

Usage: $0 [OPTIONS] <kernel> <rootfs>

Arguments:
    kernel    Path to kernel image (bzImage, Image, etc.)
    rootfs    Path to root filesystem (rootfs.ext2, rootfs.img, etc.)

Options:
    -a, --arch ARCH        Architecture (x86_64, aarch64) [default: x86_64]
    -m, --memory SIZE      Memory size (e.g., 1G, 512M) [default: 512M]
    -t, --timeout SEC      Boot timeout in seconds [default: 300]
    -v, --verbose          Verbose output
    -k, --kvm             Enable KVM acceleration (x86_64 only)
    -n, --network TYPE     Network type (user, bridge) [default: user]
    -p, --ssh-port PORT   SSH port for host forwarding [default: 2222]
    -s, --serial-port PORT Serial port for host forwarding [default: 5555]
    --test-type TYPE      Test type: basic, network, ssh, full [default: basic]
    -h, --help            Show this help message

Examples:
    $0 buildroot/output/images/bzImage buildroot/output/images/rootfs.ext2
    $0 --arch aarch64 --test-type network buildroot/output/images/Image buildroot/output/images/rootfs.ext2
    $0 --kvm --test-type full --verbose buildroot/output/images/bzImage buildroot/output/images/rootfs.ext2

Test Types:
    basic    - Basic boot and systemd health check
    network   - Basic tests plus network connectivity
    ssh       - Network tests plus SSH accessibility
    full      - All tests including package installation and system performance

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

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test result functions
test_passed() {
    local test_name="$1"
    echo "✅ $test_name: PASSED"
    ((TESTS_PASSED++))
}

test_failed() {
    local test_name="$1"
    local reason="$2"
    echo "❌ $test_name: FAILED - $reason"
    ((TESTS_FAILED++))
}

test_skipped() {
    local test_name="$1"
    local reason="$2"
    echo "⏭️  $test_name: SKIPPED - $reason"
    ((TESTS_SKIPPED++))
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--arch)
                ARCH="$2"
                shift 2
                ;;
            -m|--memory)
                MEMORY="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -k|--kvm)
                KVM=true
                shift
                ;;
            -n|--network)
                NETWORKING="$2"
                shift 2
                ;;
            -p|--ssh-port)
                SSH_PORT="$2"
                shift 2
                ;;
            -s|--serial-port)
                SERIAL_PORT="$2"
                shift 2
                ;;
            --test-type)
                TEST_TYPE="$2"
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
                if [[ -z "$KERNEL" ]]; then
                    KERNEL="$1"
                elif [[ -z "$ROOTFS" ]]; then
                    ROOTFS="$1"
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
    if [[ -z "$KERNEL" ]]; then
        print_error "Kernel image path is required"
        show_help
        exit 1
    fi
    
    if [[ -z "$ROOTFS" ]]; then
        print_error "Root filesystem path is required"
        show_help
        exit 1
    fi
    
    if [[ ! -f "$KERNEL" ]]; then
        print_error "Kernel image not found: $KERNEL"
        exit 1
    fi
    
    if [[ ! -f "$ROOTFS" ]]; then
        print_error "Root filesystem not found: $ROOTFS"
        exit 1
    fi
    
    case "$ARCH" in
        x86_64)
            if [[ "$KVM" == true ]] && ! kvm-ok; then
                print_warning "KVM not available, disabling KVM acceleration"
                KVM=false
            fi
            ;;
        aarch64)
            if [[ "$KVM" == true ]]; then
                print_warning "KVM not supported for aarch64, disabling"
                KVM=false
            fi
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    case "$TEST_TYPE" in
        basic|network|ssh|full)
            ;;
        *)
            print_error "Invalid test type: $TEST_TYPE"
            show_help
            exit 1
            ;;
    esac
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    # Check for QEMU
    if ! command -v qemu-system-x86_64 &> /dev/null && ! command -v qemu-system-aarch64 &> /dev/null; then
        missing+=("qemu-system")
    fi
    
    # Check for SSH client
    if [[ "$TEST_TYPE" =~ (ssh|full) ]] && ! command -v ssh &> /dev/null; then
        missing+=("openssh-client")
    fi
    
    # Check for netcat
    if [[ "$TEST_TYPE" =~ (network|ssh|full) ]] && ! command -v nc &> /dev/null; then
        missing+=("netcat")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        print_info "Install with: sudo apt-get install ${missing[*]}"
        exit 1
    fi
}

# Build QEMU command
build_qemu_cmd() {
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
    
    QEMU_CMD="$qemu_cmd"
    
    # Build command arguments
    QEMU_ARGS=(
        "-m" "$MEMORY"
        "-kernel" "$KERNEL"
        "-hda" "$ROOTFS"
        "-append" "root=/dev/sda console=ttyS0,115200n8"
        "-nographic"
        "-no-reboot"
        "-serial" "telnet:localhost:$SERIAL_PORT,server,nowait"
        "-netdev" "type=$NETWORKING,id=net0"
        "-device" "virtio-net-pci,netdev=net0"
        "-device" "virtio-rng-pci"
    )
    
    # Add KVM if enabled
    if [[ "$KVM" == true ]]; then
        QEMU_ARGS+=("-enable-kvm" "-cpu" "host")
    fi
    
    # Add SSH port forwarding
    if [[ "$TEST_TYPE" =~ (ssh|full) ]]; then
        QEMU_ARGS+=("-netdev" "user,id=net0,hostfwd=tcp::$SSH_PORT-:22")
    fi
    
    # Add QMP for monitoring
    QEMU_ARGS+=("-qmp" "unix:$TEMP_DIR/qmp.sock,server,nowait")
    
    if [[ "$VERBOSE" == true ]]; then
        print_info "QEMU command: $QEMU_CMD ${QEMU_ARGS[*]}"
    fi
}

# Wait for system boot
wait_for_boot() {
    print_info "Waiting for system to boot (timeout: ${TIMEOUT}s)..."
    
    # Use telnet to connect to serial port
    local boot_timeout="$TIMEOUT"
    local boot_start=$(date +%s)
    
    while true; do
        # Check if we can connect to serial port
        if echo "" | timeout 5 nc localhost "$SERIAL_PORT" 2>/dev/null | grep -q "login\|root\|buildroot" 2>/dev/null; then
            print_success "System boot detected"
            return 0
        fi
        
        # Check timeout
        local current_time=$(date +%s)
        if [[ $((current_time - boot_start)) -gt $boot_timeout ]]; then
            print_error "Boot timeout after ${TIMEOUT}s"
            return 1
        fi
        
        sleep 2
    done
}

# Run basic tests
run_basic_tests() {
    print_test "Running basic system tests..."
    
    # Test 1: System is responsive
    if echo "" | nc localhost "$SERIAL_PORT" 2>/dev/null | timeout 5 grep -q "login\|root\|#" 2>/dev/null; then
        test_passed "System Responsiveness"
    else
        test_failed "System Responsiveness" "No system response"
        return 1
    fi
    
    # Test 2: Check for login prompt
    if echo "root" | nc localhost "$SERIAL_PORT" 2>/dev/null | timeout 5 grep -q "Password\|#\|root@" 2>/dev/null; then
        test_passed "Login Prompt Available"
    else
        test_failed "Login Prompt Available" "No login prompt detected"
    fi
    
    # Test 3: Check basic system processes
    if echo "ps" | nc localhost "$SERIAL_PORT" 2>/dev/null | timeout 5 grep -q "init\|systemd" 2>/dev/null; then
        test_passed "System Processes Running"
    else
        test_failed "System Processes Running" "No system processes found"
    fi
    
    # Test 4: Check filesystem mounting
    if echo "mount" | nc localhost "$SERIAL_PORT" 2>/dev/null | timeout 5 grep -q "/dev.*on.*type.*ext" 2>/dev/null; then
        test_passed "Filesystem Mounted"
    else
        test_failed "Filesystem Mounted" "No filesystem mount detected"
    fi
}

# Run network tests
run_network_tests() {
    print_test "Running network connectivity tests..."
    
    # Test 1: Network interface up
    if echo "ip link show" | nc localhost "$SERIAL_PORT" 2>/dev/null | timeout 5 grep -q "eth0.*UP\|enp.*UP" 2>/dev/null; then
        test_passed "Network Interface Up"
    else
        test_failed "Network Interface Up" "No active network interface"
        return 1
    fi
    
    # Test 2: IP address assigned
    if echo "ip addr show" | nc localhost "$SERIAL_PORT" 2>/dev/null | timeout 5 grep -q "inet.*192.168\|inet.*10\." 2>/dev/null; then
        test_passed "IP Address Assigned"
    else
        test_failed "IP Address Assigned" "No IP address found"
    fi
    
    # Test 3: DNS resolution
    if echo "nslookup google.com" | nc localhost "$SERIAL_PORT" 2>/dev/null | timeout 10 grep -q "Address\|google.com" 2>/dev/null; then
        test_passed "DNS Resolution"
    else
        test_failed "DNS Resolution" "Cannot resolve DNS"
    fi
}

# Run SSH tests
run_ssh_tests() {
    print_test "Running SSH accessibility tests..."
    
    # Create SSH config for non-interactive testing
    cat > "$SSH_CONFIG" << EOF
Host qemu-test
    HostName localhost
    Port $SSH_PORT
    User root
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ConnectTimeout 10
    ServerAliveInterval 10
    ServerAliveCountMax 3
EOF
    
    # Wait for SSH to be available
    local ssh_timeout=60
    local ssh_start=$(date +%s)
    
    print_info "Waiting for SSH to be available..."
    
    while true; do
        if ssh -F "$SSH_CONFIG" -o ConnectTimeout=5 qemu-test "echo 'SSH_READY'" 2>/dev/null | grep -q "SSH_READY"; then
            test_passed "SSH Service Running"
            break
        fi
        
        # Check timeout
        local current_time=$(date +%s)
        if [[ $((current_time - ssh_start)) -gt $ssh_timeout ]]; then
            test_failed "SSH Service Running" "SSH service not available"
            return 1
        fi
        
        sleep 2
    done
    
    # Test SSH file transfer
    if echo "test-$(date +%s)" | ssh -F "$SSH_CONFIG" qemu-test "cat > /tmp/ssh_test.txt" 2>/dev/null; then
        test_passed "SSH File Transfer"
    else
        test_failed "SSH File Transfer" "Cannot transfer files via SSH"
    fi
    
    # Test SSH command execution
    if ssh -F "$SSH_CONFIG" qemu-test "whoami" 2>/dev/null | grep -q "root"; then
        test_passed "SSH Command Execution"
    else
        test_failed "SSH Command Execution" "Cannot execute commands via SSH"
    fi
}

# Run full system tests
run_full_tests() {
    print_test "Running comprehensive system tests..."
    
    # Test 1: Package management
    if ssh -F "$SSH_CONFIG" qemu-test "which opkg && opkg --version" 2>/dev/null; then
        test_passed "Package Management"
    else
        test_failed "Package Management" "Package manager not available"
    fi
    
    # Test 2: System performance
    local cpu_test=$(ssh -F "$SSH_CONFIG" qemu-test "dd if=/dev/zero of=/dev/null bs=1M count=100 2>&1 | grep -o '[0-9.]* MB/s'" 2>/dev/null || echo "0")
    if [[ "$cpu_test" =~ [1-9] ]]; then
        test_passed "System Performance" "Disk speed: $cpu_test"
    else
        test_failed "System Performance" "Poor performance detected"
    fi
    
    # Test 3: Memory usage
    local memory_info=$(ssh -F "$SSH_CONFIG" qemu-test "free -m" 2>/dev/null || echo "")
    if echo "$memory_info" | grep -q "Mem\|Total"; then
        test_passed "Memory Information"
    else
        test_failed "Memory Information" "Cannot get memory info"
    fi
    
    # Test 4: System logs
    if ssh -F "$SSH_CONFIG" qemu-test "test -d /var/log && ls /var/log" 2>/dev/null; then
        test_passed "System Logging"
    else
        test_failed "System Logging" "No system logs available"
    fi
    
    # Test 5: Hello World test
    local hello_output=$(ssh -F "$SSH_CONFIG" qemu-test 'echo "Hello World! BuildRoot Linux OS Test Passed!"' 2>/dev/null || echo "")
    if echo "$hello_output" | grep -q "Hello World"; then
        test_passed "Hello World Test"
    else
        test_failed "Hello World Test" "Hello World test failed"
    fi
}

# Start QEMU
start_qemu() {
    print_info "Starting QEMU with $ARCH architecture..."
    
    # Create log file
    exec 3< <(timeout "$TIMEOUT" "$QEMU_CMD" "${QEMU_ARGS[@]}" 2>&1 | tee "$SERIAL_LOG")
    QEMU_PID=$!
    
    # Give QEMU a moment to start
    sleep 3
    
    # Check if QEMU process is running
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        print_error "QEMU failed to start"
        return 1
    fi
    
    print_info "QEMU started (PID: $QEMU_PID)"
}

# Main test execution
run_tests() {
    print_info "Running test suite: $TEST_TYPE"
    
    case "$TEST_TYPE" in
        basic)
            run_basic_tests
            ;;
        network)
            run_basic_tests
            run_network_tests
            ;;
        ssh)
            run_basic_tests
            run_network_tests
            run_ssh_tests
            ;;
        full)
            run_basic_tests
            run_network_tests
            run_ssh_tests
            run_full_tests
            ;;
    esac
}

# Print test summary
print_summary() {
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    
    echo ""
    echo "=========================================="
    echo "🧪 QEMU Test Summary"
    echo "=========================================="
    echo "Test Type: $TEST_TYPE"
    echo "Architecture: $ARCH"
    echo "Kernel: $KERNEL"
    echo "Rootfs: $ROOTFS"
    echo ""
    echo "Results:"
    echo "✅ Passed: $TESTS_PASSED"
    echo "❌ Failed: $TESTS_FAILED"
    echo "⏭️  Skipped: $TESTS_SKIPPED"
    echo "📊 Total: $total_tests"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        print_success "All tests passed! 🎉"
        echo ""
        echo "📋 System is ready for use"
        echo "🔍 Logs saved to: $SERIAL_LOG"
        exit 0
    else
        echo ""
        print_error "Some tests failed"
        echo ""
        echo "🔍 Check logs: $SERIAL_LOG"
        exit 1
    fi
}

# Main function
main() {
    echo "🧪 QEMU Test Script for BuildRoot Linux OS"
    echo "============================================"
    
    parse_args "$@"
    validate_inputs
    check_dependencies
    build_qemu_cmd
    start_qemu
    wait_for_boot
    run_tests
    print_summary
}

# Run main function with all arguments
main "$@"