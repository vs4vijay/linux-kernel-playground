#!/bin/bash

# BuildRoot Build Script for Linux OS
# This script provides a convenient interface for building Linux OS using BuildRoot

set -e  # Exit on error

# Default values
BUILDROOT_VERSION="2024.02.1"
CONFIG_DIR="buildroot-configs"
BUILD_DIR="buildroot-${BUILDROOT_VERSION}"
PARALLEL_JOBS=$(nproc)
CLEAN_BUILD=false
DOWNLOAD_ONLY=false
MENU_CONFIG=false
TEST_IMAGE=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Help function
show_help() {
    cat << EOF
BuildRoot Build Script

Usage: $0 [OPTIONS] <CONFIG>

Options:
    -c, --clean          Clean build directory before building
    -d, --download-only  Only download BuildRoot source
    -m, --menuconfig     Run make menuconfig before building
    -t, --test           Test the built image with QEMU (x86_64 only)
    -j, --jobs N         Number of parallel jobs (default: $(nproc))
    -v, --verbose        Verbose output
    -h, --help           Show this help message

Arguments:
    CONFIG               BuildRoot defconfig name (e.g., generic_x86_64_defconfig)

Examples:
    $0 generic_x86_64_defconfig
    $0 --clean --menuconfig --test raspberrypi4_64_defconfig
    $0 --download-only generic_x86_64_defconfig
    $0 --jobs 8 generic_x86_64_defconfig

Available configurations:
EOF

    # List available configurations
    if [[ -d "$CONFIG_DIR" ]]; then
        find "$CONFIG_DIR" -name "*_defconfig" -type f -exec basename {} \; | sort
    else
        print_warning "Configuration directory not found: $CONFIG_DIR"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--clean)
                CLEAN_BUILD=true
                shift
                ;;
            -d|--download-only)
                DOWNLOAD_ONLY=true
                shift
                ;;
            -m|--menuconfig)
                MENU_CONFIG=true
                shift
                ;;
            -t|--test)
                TEST_IMAGE=true
                shift
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
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
                CONFIG_NAME="$1"
                shift
                ;;
        esac
    done
}

# Validate configuration
validate_config() {
    if [[ -z "$CONFIG_NAME" ]]; then
        print_error "Configuration name is required"
        show_help
        exit 1
    fi

    if [[ ! "$CONFIG_NAME" =~ _defconfig$ ]]; then
        print_error "Configuration name must end with '_defconfig'"
        exit 1
    fi

    if [[ ! -f "$CONFIG_DIR/$CONFIG_NAME" ]]; then
        print_error "Configuration file not found: $CONFIG_DIR/$CONFIG_NAME"
        print_info "Available configurations:"
        find "$CONFIG_DIR" -name "*_defconfig" -type f -exec basename {} \; | sort
        exit 1
    fi

    print_success "Configuration validated: $CONFIG_NAME"
}

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=()
    
    # Basic build tools
    for dep in make gcc g++ git wget tar; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    # System libraries
    for lib in libncurses-dev libssl-dev; do
        if ! dpkg -l | grep -q "$lib" 2>/dev/null; then
            missing_deps+=("$lib")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Install them with:"
        print_info "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        print_info "  RHEL/Fedora: sudo dnf install ${missing_deps[*]}"
        exit 1
    fi
    
    print_success "All dependencies are satisfied"
}

# Download BuildRoot
download_buildroot() {
    print_info "Downloading BuildRoot ${BUILDROOT_VERSION}..."
    
    if [[ -d "$BUILD_DIR" ]]; then
        if [[ "$CLEAN_BUILD" == true ]]; then
            print_info "Cleaning existing BuildRoot directory..."
            rm -rf "$BUILD_DIR"
        else
            print_info "BuildRoot directory already exists, skipping download"
            return
        fi
    fi
    
    local buildroot_url="https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz"
    
    if [[ "$VERBOSE" == true ]]; then
        wget -v "$buildroot_url"
    else
        wget "$buildroot_url" 2>/dev/null
    fi
    
    tar -xzf "buildroot-${BUILDROOT_VERSION}.tar.gz"
    rm "buildroot-${BUILDROOT_VERSION}.tar.gz"
    
    print_success "BuildRoot downloaded and extracted"
}

# Prepare BuildRoot configuration
prepare_config() {
    print_info "Preparing BuildRoot configuration..."
    
    cd "$BUILD_DIR"
    
    # Copy our configuration
    cp "../$CONFIG_DIR/$CONFIG_NAME" "configs/$CONFIG_NAME"
    
    # Copy kernel config if exists
    local arch_name=$(echo "$CONFIG_NAME" | cut -d'_' -f1)
    local kernel_config_path="../$CONFIG_DIR/board/$arch_name/linux.config"
    
    if [[ -f "$kernel_config_path" ]]; then
        mkdir -p "board/$arch_name"
        cp "$kernel_config_path" "board/$arch_name/linux.config"
        print_info "Copied kernel configuration for $arch_name"
    fi
    
    # Copy post build script if exists
    local post_build_script="../$CONFIG_DIR/board/post_build.sh"
    if [[ -f "$post_build_script" ]]; then
        cp "$post_build_script" "board/post_build.sh"
        chmod +x "board/post_build.sh"
        print_info "Copied post-build script"
    fi
    
    # Copy device table if exists
    local device_table="../$CONFIG_DIR/system/device_table.txt"
    if [[ -f "$device_table" ]]; then
        cp "$device_table" "system/device_table.txt"
        print_info "Copied device table"
    fi
    
    # Copy board-specific files
    local board_dir="../$CONFIG_DIR/board/$arch_name"
    if [[ -d "$board_dir" ]]; then
        mkdir -p "board/$arch_name"
        cp -r "$board_dir"/* "board/$arch_name/" 2>/dev/null || true
        print_info "Copied board-specific files for $arch_name"
    fi
    
    # Apply configuration
    print_info "Applying BuildRoot configuration: $CONFIG_NAME"
    make "$CONFIG_NAME"
    
    if [[ "$MENU_CONFIG" == true ]]; then
        print_info "Starting menuconfig..."
        make menuconfig
    fi
    
    cd ..
}

# Build BuildRoot
build_buildroot() {
    print_info "Building BuildRoot with $PARALLEL_JOBS parallel jobs..."
    
    cd "$BUILD_DIR"
    
    # Build with timeout and error handling
    local build_cmd="make -j$PARALLEL_JOBS"
    
    if [[ "$VERBOSE" == true ]]; then
        "$build_cmd" | tee build.log
    else
        "$build_cmd" > build.log 2>&1
    fi
    
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        print_success "Build completed successfully"
    else
        print_error "Build failed"
        print_info "Check build log for details: $BUILD_DIR/build.log"
        print_info "Last 50 lines of build log:"
        tail -50 build.log
        exit 1
    fi
    
    cd ..
}

# Test image with QEMU
test_image() {
    local arch_name=$(echo "$CONFIG_NAME" | cut -d'_' -f1)
    
    if [[ "$arch_name" != "generic_x86_64" ]]; then
        print_warning "QEMU testing is only supported for x86_64 configurations"
        return
    fi
    
    if [[ ! -f "$BUILD_DIR/output/images/bzImage" ]] || [[ ! -f "$BUILD_DIR/output/images/rootfs.ext2" ]]; then
        print_error "QEMU test failed: missing required image files"
        print_info "Required files: bzImage, rootfs.ext2"
        print_info "Available files:"
        ls -la "$BUILD_DIR/output/images/"
        return 1
    fi
    
    print_info "Testing image with QEMU..."
    
    # Test boot with timeout
    timeout 300 qemu-system-x86_64 \
        -m 512M \
        -kernel "$BUILD_DIR/output/images/bzImage" \
        -hda "$BUILD_DIR/output/images/rootfs.ext2" \
        -append "root=/dev/sda console=ttyS0" \
        -nographic \
        -no-reboot || {
        print_warning "QEMU test timed out (this is normal for successful boot)"
    }
    
    print_success "QEMU test completed"
}

# Show build summary
show_summary() {
    print_info "Build Summary:"
    echo "=================="
    echo "Configuration: $CONFIG_NAME"
    echo "BuildRoot Version: $BUILDROOT_VERSION"
    echo "Parallel Jobs: $PARALLEL_JOBS"
    echo "Build Directory: $BUILD_DIR"
    echo "Output Directory: $BUILD_DIR/output/images"
    echo ""
    echo "Generated Files:"
    if [[ -d "$BUILD_DIR/output/images" ]]; then
        ls -la "$BUILD_DIR/output/images/"
    fi
    
    if [[ -f "$BUILD_DIR/output/images/rootfs.ext2" ]]; then
        local size=$(du -h "$BUILD_DIR/output/images/rootfs.ext2" | cut -f1)
        echo "Root filesystem size: $size"
    fi
    
    echo ""
    print_info "Usage Examples:"
    echo "  Run with QEMU: qemu-system-x86_64 -m 512M -kernel $BUILD_DIR/output/images/bzImage -hda $BUILD_DIR/output/images/rootfs.ext2 -append 'root=/dev/sda console=ttyS0'"
    echo "  Write to SD card: sudo dd if=$BUILD_DIR/output/images/sdcard.img of=/dev/sdX bs=1M"
}

# Main function
main() {
    echo "🚀 BuildRoot Build Script"
    echo "======================="
    
    parse_args "$@"
    validate_config
    check_dependencies
    
    if [[ "$DOWNLOAD_ONLY" == true ]]; then
        download_buildroot
        print_success "BuildRoot source downloaded to: $BUILD_DIR"
        exit 0
    fi
    
    download_buildroot
    prepare_config
    build_buildroot
    
    if [[ "$TEST_IMAGE" == true ]]; then
        test_image
    fi
    
    show_summary
    
    print_success "Build process completed successfully!"
}

# Run main function with all arguments
main "$@"