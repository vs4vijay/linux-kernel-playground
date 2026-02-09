# QEMU Testing System

This directory contains comprehensive QEMU testing scripts for BuildRoot Linux OS builds.

## Files

### `test-qemu.sh`
Interactive QEMU testing script with multiple test types:

```bash
# Basic usage
./test-qemu.sh buildroot/output/images/bzImage buildroot/output/images/rootfs.ext2

# Advanced usage
./test-qemu.sh --arch aarch64 --test-type ssh --verbose \
  buildroot/output/images/Image buildroot/output/images/rootfs.ext2
```

**Test Types:**
- `basic` - Boot test and system health check
- `network` - Basic tests plus network connectivity
- `ssh` - Network tests plus SSH accessibility
- `full` - Comprehensive testing including package management

### `test-ci.sh`
Automated CI testing script for GitHub Actions:

```bash
# Basic usage
./test-ci.sh --arch x86_64 --suite basic --timeout 300 buildroot/output

# Full testing
./test-ci.sh --arch x86_64 --suite full --timeout 600 buildroot/output
```

**Test Suites:**
- `basic` - Quick boot and Hello World test
- `network` - Include network connectivity tests
- `ssh` - Include SSH service tests (not for CI)
- `full` - Comprehensive testing with package management

## Features

### Test Coverage

#### Boot Tests
- ✅ Kernel loading verification
- ✅ Init system startup
- ✅ Login prompt availability
- ✅ System process monitoring
- ✅ Filesystem mounting verification

#### System Tests
- ✅ Filesystem health checks
- ✅ Memory allocation monitoring
- ✅ Device node creation
- ✅ System service status

#### Network Tests
- ✅ Network interface configuration
- ✅ IP address assignment
- ✅ DNS resolution testing
- ✅ Network connectivity verification

#### Application Tests
- ✅ Package manager functionality
- ✅ Command execution verification
- ✅ File operations testing
- ✅ SSH service accessibility
- ✅ Performance benchmarking

#### Hello World Tests
- ✅ Automated "Hello World!" message execution
- ✅ System information collection
- ✅ Performance metrics gathering
- ✅ Error detection and reporting

### Integration

#### GitHub Actions
- ✅ Automatic testing in CI/CD pipeline
- ✅ Test result artifacts (JSON + logs)
- ✅ PR gate protection with test validation
- ✅ Failed test prevention for main branch

#### Local Development
- ✅ Makefile integration for easy testing
- ✅ Multiple test suite options
- ✅ Interactive manual testing
- ✅ Debug output and logging

## Usage Examples

### Local Testing

```bash
# Quick test
make build-generic_x86_64_defconfig
make test

# Different test suites
make test-basic      # Boot and system health
make test-network     # Include network tests
make test-full        # Comprehensive testing
make test-interactive # Interactive manual testing
```

### CI/CD Integration

The QEMU testing is integrated into:

1. **PR Workflow**: Tests x86_64 configurations before merging
2. **Release Workflow**: Full testing for all release builds
3. **Test Results**: JSON reports and detailed logs
4. **Validation**: Failed tests prevent PR merging

### ARM64 Support

#### CI/CD Limitations
ARM64 configurations (raspberrypi4_64_defconfig, arm64_dev_defconfig) use build validation only in CI due to:

- Limited QEMU ARM64 support in GitHub Actions runners
- Longer boot times for ARM64 systems
- Resource constraints in CI environment
- Focus on x86_64 for CI gate (most common use case)

#### Local Testing
ARM64 configurations can be tested locally:

```bash
# Build and test ARM64
make build-raspberrypi4_64_defconfig
./test-qemu.sh --arch aarch64 --test-type full \
  buildroot/output/images/Image buildroot/output/images/rootfs.ext2

# Or use CI script locally
./test-ci.sh --arch aarch64 --suite full buildroot/output
```

### Error Handling

- Graceful timeout handling for hanging systems
- Proper cleanup of QEMU processes
- Detailed error logging and reporting
- Resource validation and dependency checking
- Fail-fast behavior for CI environments

### Output

#### Test Results
- **JSON Format**: Structured results for automated parsing
- **Human Readable**: Summary reports for manual review
- **Detailed Logs**: Full QEMU output for debugging
- **Performance Metrics**: System benchmarking data

#### Artifacts
- **CI Artifacts**: Uploaded to GitHub Actions
- **Local Logs**: Saved to temporary files
- **Checksums**: SHA256 and MD5 verification files
- **Build Reports**: Detailed build information

## Troubleshooting

### Common Issues

1. **Missing QEMU**: Install with `sudo apt-get install qemu-system-x86_64 qemu-system-aarch64`
2. **Build artifacts not found**: Ensure build completed before testing
3. **Timeout errors**: Increase timeout value or check system resources
4. **Permission denied**: Ensure QEMU has necessary permissions
5. **Architecture mismatch**: Use correct architecture for kernel/rootfs pair

### Debug Mode

Enable debug output:

```bash
./test-qemu.sh --verbose --test-type basic bzImage rootfs.ext2
./test-ci.sh --arch x86_64 --suite basic --verbose buildroot/output
```

### Logging

Test scripts provide comprehensive logging:
- Console output with colored status messages
- Detailed QEMU boot logs
- JSON-formatted test results
- Performance metrics and system information

## Contributing

When adding new configurations or tests:

1. Update both test scripts with new architecture support
2. Update CI workflows with appropriate testing strategy
3. Test locally before submitting PR
4. Include test results in CI validation
5. Update documentation with new test coverage

## Best Practices

1. **Always test boot functionality** before releasing
2. **Use appropriate test timeouts** for system complexity
3. **Clean up resources** to prevent process leaks
4. **Validate all input parameters** to prevent errors
5. **Document test limitations** and requirements

This QEMU testing system ensures every BuildRoot Linux OS build boots correctly, runs "Hello World!" tests, and maintains system health across all supported configurations! 🚀