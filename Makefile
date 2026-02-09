# Makefile for BuildRoot Linux OS Development
# This Makefile provides convenient targets for building and managing Linux OS configurations

# Default values
BUILDROOT_VERSION := 2024.02.1
BUILD_DIR := buildroot-$(BUILDROOT_VERSION)
CONFIG_DIR := buildroot-configs
PARALLEL_JOBS := $(shell nproc)
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v1.0.0")

# Available configurations
X86_CONFIGS := $(notdir $(wildcard $(CONFIG_DIR)/x86_64/*_defconfig))
ARM64_CONFIGS := $(notdir $(wildcard $(CONFIG_DIR)/arm64/*_defconfig))
ALL_CONFIGS := $(notdir $(wildcard $(CONFIG_DIR)/**/*_defconfig))

# Default configuration
DEFAULT_CONFIG := generic_x86_64_defconfig

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

.PHONY: help list-configs download clean test install-deps menuconfig

# Default target
help:
	@echo "BuildRoot Linux OS Makefile"
	@echo "=========================="
	@echo ""
	@echo "Available targets:"
	@echo "  help              - Show this help message"
	@echo "  list-configs      - List all available configurations"
	@echo "  download          - Download BuildRoot source"
	@echo "  clean             - Clean build directory"
	@echo "  install-deps      - Install required dependencies (Ubuntu/Debian)"
	@echo ""
	@echo "Build targets:"
	@echo "  build             - Build default configuration ($(DEFAULT_CONFIG))"
	@echo "  build-<CONFIG>    - Build specific configuration"
	@echo "  menuconfig        - Run menuconfig on current configuration"
	@echo "  test              - Test built image with QEMU"
	@echo ""
	@echo "Development targets:"
	@echo "  defconfig-<NAME>  - Create new defconfig from current config"
	@echo "  saveconfig        - Save current configuration"
	@echo "  oldconfig         - Update config with new options"
	@echo ""
	@echo "Available configurations:"
	@$(MAKE) list-configs

# List available configurations
list-configs:
	@echo "$(BLUE)x86_64 Configurations:$(NC)"
	@if [ -n "$(X86_CONFIGS)" ]; then \
		for config in $(X86_CONFIGS); do echo "  $$config"; done; \
	else \
		echo "  No x86_64 configurations found"; \
	fi
	@echo ""
	@echo "$(BLUE)ARM64 Configurations:$(NC)"
	@if [ -n "$(ARM64_CONFIGS)" ]; then \
		for config in $(ARM64_CONFIGS); do echo "  $$config"; done; \
	else \
		echo "  No ARM64 configurations found"; \
	fi
	@echo ""
	@echo "$(GREEN)Default configuration: $(DEFAULT_CONFIG)$(NC)"

# Download BuildRoot source
download:
	@echo "$(BLUE)[INFO] Downloading BuildRoot $(BUILDROOT_VERSION)...$(NC)"
	@if [ ! -d "$(BUILDROOT_DIR)" ]; then \
		wget https://buildroot.org/downloads/buildroot-$(BUILDROOT_VERSION).tar.gz && \
		tar -xzf buildroot-$(BUILDROOT_VERSION).tar.gz && \
		rm buildroot-$(BUILDROOT_VERSION).tar.gz && \
		echo "$(GREEN)[SUCCESS] BuildRoot downloaded$(NC)"; \
	else \
		echo "$(YELLOW)[WARNING] BuildRoot directory already exists$(NC)"; \
	fi

# Install dependencies (Ubuntu/Debian)
install-deps:
	@echo "$(BLUE)[INFO] Installing dependencies...$(NC)"
	@sudo apt-get update
	@sudo apt-get install -y \
		build-essential libncurses5-dev libssl-dev libpcap-dev \
		net-tools git rsync unzip wget curl bc python3 python3-pip \
		qemu-system-x86 qemu-system-arm qemu-utils \
		cpio kmod udev device-tree-compiler swig \
		libncursesw5-dev bison flex libelf-dev \
		bc kmod udev
	@echo "$(GREEN)[SUCCESS] Dependencies installed$(NC)"

# Clean build directory
clean:
	@echo "$(YELLOW)[WARNING] Cleaning build directory...$(NC)"
	@if [ -d "$(BUILDROOT_DIR)" ]; then \
		rm -rf $(BUILDROOT_DIR); \
		echo "$(GREEN)[SUCCESS] Build directory cleaned$(NC)"; \
	else \
		echo "$(YELLOW)[WARNING] No build directory found$(NC)"; \
	fi

# Prepare configuration (internal function)
prepare-config = \
	@if [ ! -d "$(BUILDROOT_DIR)" ]; then \
		echo "$(RED)[ERROR] BuildRoot not found, run 'make download' first$(NC)"; \
		exit 1; \
	fi; \
	cd $(BUILDROOT_DIR) && \
	if [ -f "../$(CONFIG_DIR)/$(1)" ]; then \
		cp "../$(CONFIG_DIR)/$(1)" "configs/$(1)"; \
		echo "$(BLUE)[INFO] Applied configuration: $(1)$(NC)"; \
	else \
		echo "$(RED)[ERROR] Configuration not found: $(1)$(NC)"; \
		exit 1; \
	fi; \
	arch=$$(echo "$(1)" | cut -d'_' -f1); \
	if [ -f "../$(CONFIG_DIR)/board/$$arch/linux.config" ]; then \
		mkdir -p "board/$$arch" && \
		cp "../$(CONFIG_DIR)/board/$$arch/linux.config" "board/$$arch/"; \
	fi; \
	if [ -f "../$(CONFIG_DIR)/board/post_build.sh" ]; then \
		cp "../$(CONFIG_DIR)/board/post_build.sh" "board/"; \
		chmod +x "board/post_build.sh"; \
	fi; \
	if [ -f "../$(CONFIG_DIR)/system/device_table.txt" ]; then \
		cp "../$(CONFIG_DIR)/system/device_table.txt" "system/"; \
	fi; \
	make $(1)

# Build specific configuration
define BUILD_CONFIG
build-$(1):
	@echo "$(BLUE)[INFO] Building $(1)...$(NC)"
	@if [ ! -f "$(CONFIG_DIR)/$(1)" ]; then \
		echo "$(RED)[ERROR] Configuration not found: $(1)$(NC)"; \
		echo "$(YELLOW)[INFO] Run 'make list-configs' to see available configurations$(NC)"; \
		exit 1; \
	fi
	@$(call prepare-config,$(1))
	@cd $(BUILDROOT_DIR) && \
	echo "$(BLUE)[INFO] Building with $(PARALLEL_JOBS) parallel jobs...$(NC)" && \
	make -j$(PARALLEL_JOBS) && \
	echo "$(GREEN)[SUCCESS] Build completed: $(1)$(NC)"
	@$(MAKE) show-build-info CONFIG=$(1)
endef

# Generate build targets for all configurations
$(foreach config,$(ALL_CONFIGS),$(eval $(call BUILD_CONFIG,$(config))))

# Default build target
build: build-$(DEFAULT_CONFIG)

# Show build information
show-build-info:
	@if [ -n "$(CONFIG)" ] && [ -d "$(BUILDROOT_DIR)/output/images" ]; then \
		echo "$(BLUE)[INFO] Build Information for $(CONFIG):$(NC)"; \
		echo "BuildRoot Version: $(BUILDROOT_VERSION)"; \
		echo "Configuration: $(CONFIG)"; \
		echo "Output Directory: $(BUILDROOT_DIR)/output/images"; \
		echo ""; \
		echo "Generated Files:"; \
		ls -la $(BUILDROOT_DIR)/output/images/; \
		if [ -f "$(BUILDROOT_DIR)/output/images/rootfs.ext2" ]; then \
			size=$$(du -h $(BUILDROOT_DIR)/output/images/rootfs.ext2 | cut -f1); \
			echo ""; \
			echo "Root filesystem size: $$size"; \
		fi; \
	fi

# Menuconfig
menuconfig:
	@if [ ! -d "$(BUILDROOT_DIR)" ]; then \
		echo "$(RED)[ERROR] BuildRoot not found, run 'make download' first$(NC)"; \
		exit 1; \
	fi
	@cd $(BUILDROOT_DIR) && make menuconfig

# Test with QEMU (for x86_64 configurations)
test:
	@config=$$(find $(CONFIG_DIR) -name "*_defconfig" -type f | head -1 | xargs basename)
	if [[ "$config" != *"x86_64"* ]]; then \
		echo "$(YELLOW)[WARNING] Comprehensive QEMU testing is only supported for x86_64 configurations$(NC)"; \
	else \
		if [ -f "$(BUILD_DIR)/output/images/bzImage" ] && [ -f "$(BUILD_DIR)/output/images/rootfs.ext2" ]; then \
			echo "$(BLUE)[INFO] Running comprehensive QEMU tests...$(NC)"; \
			./test-ci.sh --arch x86_64 --suite basic --timeout 300 $(BUILD_DIR)/output || { \
				echo "$(RED)[ERROR] QEMU tests failed$(NC)"; \
				exit 1; \
			} \
			echo "$(GREEN)[SUCCESS] All QEMU tests completed$(NC)"; \
		else \
			echo "$(RED)[ERROR] QEMU test failed - missing required files$(NC)"; \
			echo "Required: bzImage, rootfs.ext2"; \
			echo "Available:"; \
			ls -la $(BUILD_DIR)/output/images/ 2>/dev/null || echo "No images found"; \
		fi; \
	fi

# Advanced QEMU testing with different test suites
test-basic:
	@if [ -f "$(BUILD_DIR)/output/images/bzImage" ] && [ -f "$(BUILD_DIR)/output/images/rootfs.ext2" ]; then \
		echo "$(BLUE)[INFO] Running basic QEMU tests...$(NC)"; \
		./test-ci.sh --arch x86_64 --suite basic --timeout 300 $(BUILD_DIR)/output; \
	else \
		echo "$(RED)[ERROR] No build artifacts found$(NC)"; \
	fi

test-network:
	@if [ -f "$(BUILD_DIR)/output/images/bzImage" ] && [ -f "$(BUILD_DIR)/output/images/rootfs.ext2" ]; then \
		echo "$(BLUE)[INFO] Running network QEMU tests...$(NC)"; \
		./test-ci.sh --arch x86_64 --suite network --timeout 300 $(BUILD_DIR)/output; \
	else \
		echo "$(RED)[ERROR] No build artifacts found$(NC)"; \
	fi

test-full:
	@if [ -f "$(BUILD_DIR)/output/images/bzImage" ] && [ -f "$(BUILD_DIR)/output/images/rootfs.ext2" ]; then \
		echo "$(BLUE)[INFO] Running full QEMU test suite...$(NC)"; \
		./test-ci.sh --arch x86_64 --suite full --timeout 600 $(BUILD_DIR)/output; \
	else \
		echo "$(RED)[ERROR] No build artifacts found$(NC)"; \
	fi

# Manual QEMU testing with interactive mode
test-interactive:
	@if [ -f "$(BUILD_DIR)/output/images/bzImage" ] && [ -f "$(BUILD_DIR)/output/images/rootfs.ext2" ]; then \
		echo "$(BLUE)[INFO] Starting interactive QEMU session...$(NC)"; \
		echo "$(YELLOW)[INFO] Press Ctrl+A, X to exit QEMU$(NC)"; \
		./test-qemu.sh --arch x86_64 --test-type ssh --verbose $(BUILD_DIR)/output/images/bzImage $(BUILD_DIR)/output/images/rootfs.ext2; \
	else \
		echo "$(RED)[ERROR] No build artifacts found$(NC)"; \
	fi

# Save current configuration
saveconfig:
	@if [ ! -d "$(BUILDROOT_DIR)" ]; then \
		echo "$(RED)[ERROR] BuildRoot not found$(NC)"; \
		exit 1; \
	fi
	@cd $(BUILDROOT_DIR) && \
	echo "$(BLUE)[INFO] Saving current configuration...$(NC)" && \
	make savedefconfig && \
	echo "$(GREEN)[SUCCESS] Configuration saved to defconfig$(NC)"

# Create new defconfig
defconfig-$(NAME):
	@if [ ! -d "$(BUILDROOT_DIR)" ]; then \
		echo "$(RED)[ERROR] BuildRoot not found$(NC)"; \
		exit 1; \
	fi
	@cd $(BUILDROOT_DIR) && \
	echo "$(BLUE)[INFO] Creating defconfig: $(NAME)_defconfig$(NC)" && \
	make savedefconfig && \
	cp defconfig configs/$(NAME)_defconfig && \
	echo "$(GREEN)[SUCCESS] Created: configs/$(NAME)_defconfig$(NC)"

# Update configuration
oldconfig:
	@if [ ! -d "$(BUILDROOT_DIR)" ]; then \
		echo "$(RED)[ERROR] BuildRoot not found$(NC)"; \
		exit 1; \
	fi
	@cd $(BUILDROOT_DIR) && \
	echo "$(BLUE)[INFO] Updating configuration...$(NC)" && \
	make oldconfig && \
	echo "$(GREEN)[SUCCESS] Configuration updated$(NC)"

# Continuous integration targets
ci: download install-deps build
	@echo "$(GREEN)[SUCCESS] CI build completed$(NC)"

# Development workflow
dev-setup: download install-deps
	@echo "$(GREEN)[SUCCESS] Development environment setup complete$(NC)"
	@echo "$(BLUE)[INFO] Run 'make build' to start building$(NC)"

# Quick build without clean
quick-build:
	@if [ -d "$(BUILDROOT_DIR)" ]; then \
		cd $(BUILDROOT_DIR) && \
		echo "$(BLUE)[INFO] Quick build with $(PARALLEL_JOBS) jobs...$(NC)" && \
		make -j$(PARALLEL_JOBS) && \
		echo "$(GREEN)[SUCCESS] Quick build completed$(NC)"; \
	else \
		echo "$(RED)[ERROR] BuildRoot not found, run 'make download' first$(NC)"; \
		exit 1; \
	fi

# Clean build artifacts only
clean-artifacts:
	@if [ -d "$(BUILDROOT_DIR)/output" ]; then \
		rm -rf $(BUILDROOT_DIR)/output; \
		echo "$(GREEN)[SUCCESS] Build artifacts cleaned$(NC)"; \
	fi

# Check dependencies status
check-deps:
	@echo "$(BLUE)[INFO] Checking dependencies...$(NC)"
	@missing=""; \
	for dep in make gcc g++ git wget tar; do \
		if ! command -v $$dep &> /dev/null; then \
			missing="$$missing $$dep"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "$(RED)[ERROR] Missing dependencies:$$missing$(NC)"; \
		echo "$(YELLOW)[INFO] Run 'make install-deps' to install them$(NC)"; \
	else \
		echo "$(GREEN)[SUCCESS] All dependencies are installed$(NC)"; \
	fi

# Show project information
info:
	@echo "$(BLUE)BuildRoot Linux OS Project Information$(NC)"
	@echo "======================================"
	@echo "BuildRoot Version: $(BUILDROOT_VERSION)"
	@echo "Build Directory: $(BUILDROOT_DIR)"
	@echo "Config Directory: $(CONFIG_DIR)"
	@echo "Parallel Jobs: $(PARALLEL_JOBS)"
	@echo "Default Config: $(DEFAULT_CONFIG)"
	@echo ""
	@echo "$(BLUE)Project Structure:$(NC)"
	@tree -L 2 . 2>/dev/null || find . -maxdepth 2 -type d -exec ls -d {} \; | sort

# Include custom rules if they exist
-include Makefile.custom