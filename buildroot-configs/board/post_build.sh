#!/bin/bash

# Post-build script for Buildroot
# This script is executed after the target filesystem is built

# Create essential directories
mkdir -p "${TARGET_DIR}"/{boot,dev,proc,sys,tmp,mnt,media}
mkdir -p "${TARGET_DIR}"/{usr/{bin,sbin,lib,include},var/{log,run,tmp}}
mkdir -p "${TARGET_DIR}"/{home,root,opt,srv}
mkdir -p "${TARGET_DIR}"/{etc/{init.d,rc.d,profile.d,udev/rules.d}}

# Set proper permissions
chmod 755 "${TARGET_DIR}"
chmod 755 "${TARGET_DIR}"/{boot,dev,proc,sys,tmp,mnt,media}
chmod 755 "${TARGET_DIR}"/{usr,var,home,root,opt,srv}
chmod 755 "${TARGET_DIR}"/usr/{bin,sbin,lib,include}
chmod 755 "${TARGET_DIR}"/var/{log,run,tmp}
chmod 700 "${TARGET_DIR}"/root
chmod 1777 "${TARGET_DIR}"/tmp
chmod 1777 "${TARGET_DIR}"/var/tmp

# Create basic configuration files
cat > "${TARGET_DIR}/etc/hostname" << EOF
buildroot-linux
EOF

cat > "${TARGET_DIR}/etc/hosts" << EOF
127.0.0.1	localhost
127.0.1.1	buildroot-linux
::1		localhost
EOF

cat > "${TARGET_DIR}/etc/fstab" << EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults        0       0
sysfs           /sys            sysfs   defaults        0       0
devtmpfs        /dev            devtmpfs defaults        0       0
tmpfs           /tmp            tmpfs   defaults        0       0
tmpfs           /var/tmp        tmpfs   defaults        0       0
EOF

cat > "${TARGET_DIR}/etc/passwd" << EOF
root:x:0:0:root:/root:/bin/sh
nobody:x:99:99:Nobody:/:/bin/false
EOF

cat > "${TARGET_DIR}/etc/group" << EOF
root:x:0:
daemon:x:1:
adm:x:2:
wheel:x:10:
nogroup:x:99:
EOF

cat > "${TARGET_DIR}/etc/shadow" << EOF
root::18773:0:99999:7:::
nobody:*:18773:0:99999:7:::
EOF

cat > "${TARGET_DIR}/etc/profile" << EOF
# System-wide environment and startup programs
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"
export PS1='[\u@\h \W]\$ '
export EDITOR="nano"
export TERM="linux"

# User specific aliases and functions
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias vi='nano'
EOF

# Create network configuration
cat > "${TARGET_DIR}/etc/network/interfaces" << EOF
# /etc/network/interfaces -- configuration file for ifup(8), ifdown(8)

# The loopback interface
auto lo
iface lo inet loopback

# Example Ethernet configuration
# auto eth0
# iface eth0 inet dhcp

# Example WiFi configuration
# auto wlan0
# iface wlan0 inet dhcp
#     wpa-driver wext
#     wpa-ssid "your-ssid"
#     wpa-psk "your-passphrase"
EOF

# Create inittab
cat > "${TARGET_DIR}/etc/inittab" << EOF
# /etc/inittab

::sysinit:/etc/init.d/rcS
::sysinit:/bin/mount -a
::sysinit:/bin/hostname -F /etc/hostname

# TTYs
::respawn:/sbin/getty -L 115200 ttyS0 vt100
::respawn:/sbin/getty -L 38400 tty1 linux
::respawn:/sbin/getty -L 38400 tty2 linux
::respawn:/sbin/getty -L 38400 tty3 linux

# Put a getty on the serial port
#::respawn:/sbin/getty -L 115200 ttyS0 vt100

# Logging
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a

# Run getty on 4-6 if not using X
tty4::respawn:/sbin/getty 38400 tty4
tty5::respawn:/sbin/getty 38400 tty5
tty6::respawn:/sbin/getty 38400 tty6
EOF

# Create init script
cat > "${TARGET_DIR}/etc/init.d/rcS" << EOF
#!/bin/sh

# rcS - System initialization script

echo "Initializing Buildroot Linux..."

# Mount virtual filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /var/tmp

# Create essential device nodes if they don't exist
if [ ! -e /dev/console ]; then
    mknod -m 622 /dev/console c 5 1
fi
if [ ! -e /dev/null ]; then
    mknod -m 666 /dev/null c 1 3
fi
if [ ! -e /dev/zero ]; then
    mknod -m 666 /dev/zero c 1 5
fi

# Set hostname
hostname -F /etc/hostname

# Start system services
echo "Starting system services..."
if [ -x /usr/sbin/sshd ]; then
    echo "Starting SSH daemon..."
    /usr/sbin/sshd &
fi

# Configure network
if [ -x /sbin/ifconfig ]; then
    echo "Configuring network interfaces..."
    ifconfig lo 127.0.0.1 netmask 255.0.0.0 up
fi

echo "Buildroot Linux initialization complete."

# Start services
echo "Starting system services..."

# Print system information
echo "==========================================="
echo "Welcome to Buildroot Linux"
echo "Kernel: $(uname -r)"
echo "Hostname: $(hostname)"
echo "==========================================="
EOF

chmod +x "${TARGET_DIR}/etc/init.d/rcS"

# Create default motd
cat > "${TARGET_DIR}/etc/motd" << EOF
Welcome to Buildroot Linux!

For help and support, visit: https://buildroot.org
EOF

# Create issue file
cat > "${TARGET_DIR}/etc/issue" << EOF
Buildroot Linux \r (\l)
EOF

echo "Post-build script completed successfully."