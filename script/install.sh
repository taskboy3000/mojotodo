#!/bin/bash
set -e

# Exit if not running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo $0)"
    exit 1
fi

APP_DIR="/opt/mojotodo"
DATA_DIR="/var/lib/mojotodo"
LOG_DIR="/var/log/mojotodo"
USER="mojotodo"
GROUP="mojotodo"

echo "=== MojoTodo Installation Script ==="

# Create system user if not exists
if ! id "$USER" &>/dev/null; then
    echo "Creating user: $USER"
    useradd --system --no-create-home --shell /usr/sbin/nologin "$USER"
else
    echo "User $USER already exists"
fi

# Create directories
echo "Creating directories..."
mkdir -p "$DATA_DIR" "$LOG_DIR"
chown "$USER:$GROUP" "$DATA_DIR" "$LOG_DIR"

# Install Perl dependencies if carton not available
if ! command -v carton &> /dev/null; then
    echo "Installing carton..."
    cpanm Carton
fi

# Install application dependencies
echo "Installing Perl dependencies..."
cd "$APP_DIR"
carton install --deployment || cpanm --installdeps .

# Copy systemd service file
echo "Installing systemd service..."
cp "$APP_DIR/mojotodo.service" /etc/systemd/system/
systemctl daemon-reload

# Enable and start service
echo "Enabling mojotodo service..."
systemctl enable mojotodo
systemctl start mojotodo

# Check status
echo ""
echo "=== Installation Complete ==="
echo "Service status:"
systemctl status mojotodo --no-pager || true

echo ""
echo "Logs:"
journalctl -u mojotodo -n 20 --no-pager || true
