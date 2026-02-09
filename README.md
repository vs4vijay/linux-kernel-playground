# BuildRoot Linux OS Playground

A comprehensive system for building custom Linux-based operating systems using BuildRoot with proper CI/CD, testing, and extensibility for multiple machine architectures.

## 🚀 Quick Start

### Prerequisites

- Linux development environment (Ubuntu/Debian recommended)
- Basic build tools (make, gcc, git, etc.)
- At least 8GB RAM and 20GB disk space for builds

### Installation

```bash
# Clone the repository
git clone https://github.com/your-username/linux-kernel-playground.git
cd linux-kernel-playground

# Install dependencies (Ubuntu/Debian)
make install-deps

# Download BuildRoot source
make download

# Build default configuration (generic x86_64)
make build
```

### Alternative: Using the Build Script

```bash
# Make the script executable
chmod +x build.sh

# Build with the script
./build.sh generic_x86_64_defconfig

# Build with options
./build.sh --clean --menuconfig --test generic_x86_64_defconfig
```

## 📋 Available Configurations

### x86_64 Configurations
- **generic_x86_64_defconfig** - Generic x86_64 system suitable for QEMU and modern hardware
  - Kernel: 6.6.21
  - Features: SystemD, X11, Desktop environment, Development tools
  - Use case: Development, testing, virtual machines

### ARM64 Configurations  
- **raspberrypi4_64_defconfig** - Raspberry Pi 4 (64-bit) optimized configuration
  - Kernel: 6.6.21 with RPi patches
  - Features: GPU acceleration, Camera support, WiFi/Bluetooth, Desktop
  - Use case: Raspberry Pi 4 single-board computers

## 🛠️ Building and Development

### Using Makefile

```bash
# List all available configurations
make list-configs

# Build specific configuration
make build-raspberrypi4_64_defconfig

# Clean build directory
make clean

# Run menuconfig to customize configuration
make menuconfig

# Test built image with QEMU (x86_64 only)
make test

# Show project information
make info
```

### Using Build Script

```bash
# Show help
./build.sh --help

# Build with clean start and menuconfig
./build.sh --clean --menuconfig generic_x86_64_defconfig

# Build and test with QEMU
./build.sh --test generic_x86_64_defconfig

# Download only (no build)
./build.sh --download-only generic_x86_64_defconfig

# Build with custom parallel jobs
./build.sh --jobs 8 generic_x86_64_defconfig
```

## 🏗️ Project Structure

```
linux-kernel-playground/
├── buildroot-configs/          # Custom BuildRoot configurations
│   ├── x86_64/                 # x86_64 specific configs
│   │   └── generic_x86_64_defconfig
│   ├── arm64/                  # ARM64 specific configs
│   │   └── raspberrypi4_64_defconfig
│   ├── board/                  # Board-specific files
│   │   ├── x86_64/
│   │   │   └── linux.config
│   │   ├── raspberrypi4/
│   │   │   ├── linux.config
│   │   │   ├── config.txt
│   │   │   └── boot.txt
│   │   └── post_build.sh
│   ├── system/                 # System-wide configurations
│   │   └── device_table.txt
│   └── package/                # Package configurations
│       └── busybox/
│           └── busybox.config
├── .github/workflows/          # CI/CD workflows
│   └── buildroot.yml
├── build.sh                    # Build script
├── Makefile                    # Makefile for development
└── README.md                   # This file
```

## 🧪 Testing

### Local Testing with QEMU

```bash
# Build and test x86_64 configuration
make build-generic_x86_64_defconfig
make test

# Or using the build script
./build.sh --test generic_x86_64_defconfig
```

### CI/CD Testing

The GitHub Actions workflow automatically:
- Validates all configuration files
- Builds all configurations in parallel
- Tests x86_64 images with QEMU
- Runs security scans
- Generates build reports
- Comments on pull requests with results

## 📝 Creating New Configurations

### Method 1: Copy and Modify Existing Config

```bash
# Copy an existing configuration
cp buildroot-configs/x86_64/generic_x86_64_defconfig buildroot-configs/x86_64/my_custom_defconfig

# Create board directory if needed
mkdir -p buildroot-configs/board/my_custom

# Copy and modify kernel config
cp buildroot-configs/board/x86_64/linux.config buildroot-configs/board/my_custom/linux.config

# Edit the configuration files
nano buildroot-configs/x86_64/my_custom_defconfig
nano buildroot-configs/board/my_custom/linux.config
```

### Method 2: Use BuildRoot Menuconfig

```bash
# Build base configuration
make build-generic_x86_64_defconfig

# Run menuconfig to customize
cd buildroot-2024.02.1
make menuconfig

# Save your configuration
make savedefconfig

# Copy the generated defconfig to your project
cp defconfig ../buildroot-configs/x86_64/my_custom_defconfig
```

### Configuration File Structure

Each defconfig should include:
- Architecture selection (BR2_x86_64, BR2_aarch64, etc.)
- Toolchain configuration
- Kernel configuration
- Package selection
- Filesystem settings
- Bootloader configuration

## 🔧 Customization Options

### Kernel Configuration

Edit the board-specific kernel config:
```bash
nano buildroot-configs/board/<arch>/linux.config
```

### Package Selection

Modify the defconfig to add/remove packages:
```bash
# Add a package
BR2_PACKAGE_<PACKAGE_NAME>=y

# Remove a package
# BR2_PACKAGE_<PACKAGE_NAME>=y
```

### Post-Build Customization

Edit the post-build script:
```bash
nano buildroot-configs/board/post_build.sh
```

## 📦 Output Files

After building, you'll find these files in `buildroot-<version>/output/images/`:

### x86_64 Output
- `bzImage` - Linux kernel
- `rootfs.ext2` - Root filesystem
- `rootfs.tar` - Root filesystem archive

### Raspberry Pi 4 Output
- `kernel8.img` - 64-bit kernel
- `bcm2711-rpi-4-b.dtb` - Device tree
- `rootfs.ext2` - Root filesystem
- `sdcard.img` - Complete SD card image

## 🏷️ Version Management

The project includes a comprehensive version management system:

### Using Version Script

```bash
# Show current version
./version.sh --version

# Bump patch version (v1.0.0 → v1.0.1)
./version.sh --bump patch

# Bump minor version (v1.0.1 → v1.1.0)
./version.sh --bump minor

# Bump major version (v1.1.0 → v2.0.0)
./version.sh --bump major

# Set specific version
./version.sh --set v2.0.0

# Bump version, create tag, and push
./version.sh --bump patch --tag --push
```

### Creating Releases

#### Automatic Release (Recommended)
1. Bump version and create tag:
   ```bash
   ./version.sh --bump patch --tag --push
   ```
2. GitHub Actions will automatically create a release

#### Manual Release
1. Create and push a tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
2. GitHub Actions will trigger the release workflow

#### Workflow Dispatch
You can also create releases manually through GitHub Actions:
1. Go to Actions → Release BuildRoot Linux OS
2. Click "Run workflow"
3. Enter version details
4. Choose whether to create a pre-release

### Release Contents

Each release includes:
- **Configuration archives** (.tar.gz, .zip) with all build artifacts
- **Checksums** (SHA256, MD5) for verification
- **Build reports** with detailed build information
- **README files** with usage instructions
- **QEMU testing** results (for applicable configurations)

### Artifact Download

Release artifacts are available through:
- **GitHub Releases**: Download from the release page
- **GitHub Actions**: Download as workflow artifacts
- **CI Artifacts**: Available for 30 days after build

### Verification

Always verify downloaded releases:

```bash
# Download the checksum file
wget https://github.com/your-repo/releases/download/v1.0.0/sha256sums.txt

# Verify your download
sha256sum -c sha256sums.txt
```

## 🚀 Deployment

### QEMU (x86_64)

```bash
qemu-system-x86_64 \
  -m 512M \
  -kernel buildroot-2024.02.1/output/images/bzImage \
  -hda buildroot-2024.02.1/output/images/rootfs.ext2 \
  -append "root=/dev/sda console=ttyS0" \
  -nographic
```

### Raspberry Pi 4

```bash
# Write to SD card
sudo dd if=buildroot-2024.02.1/output/images/sdcard.img of=/dev/sdX bs=1M

# Or manually copy files
sudo cp buildroot-2024.02.1/output/images/* /media/sdcard/boot/
```

## 🐛 Troubleshooting

### Common Issues

1. **Build fails with dependency errors**
   ```bash
   make install-deps
   ```

2. **QEMU test fails**
   - Ensure you're using an x86_64 configuration
   - Check that bzImage and rootfs.ext2 exist

3. **Configuration not found**
   ```bash
   make list-configs
   ```

4. **Build takes too long**
   - Increase parallel jobs: `./build.sh --jobs 16 <config>`
   - Use SSD storage
   - Ensure sufficient RAM

### Getting Help

- Check the build log: `buildroot-<version>/build.log`
- Review GitHub Actions build reports
- Open an issue on GitHub

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add your configuration
4. Test locally
5. Submit a pull request

### Pull Request Guidelines

- Include a clear description of changes
- Test your configuration locally
- Update documentation if needed
- Ensure CI passes

## 📚 Resources

- [BuildRoot Documentation](https://buildroot.org/manual.html)
- [Linux Kernel Documentation](https://www.kernel.org/doc/)
- [QEMU Documentation](https://www.qemu.org/docs/master/)
- [Raspberry Pi Documentation](https://www.raspberrypi.org/documentation/)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- BuildRoot project for the excellent build system
- Linux kernel developers
- Raspberry Pi Foundation
- QEMU project for virtualization support