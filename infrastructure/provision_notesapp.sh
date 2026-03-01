#!/usr/bin/env bash
# =============================================================================
# provision_notesapp.sh
# Production-grade provisioning script for Notes App on Amazon Linux 2023
# Compatible with EC2 User Data and manual execution via sudo
# =============================================================================

set -euo pipefail

# =============================================================================
# VARIABLES
# =============================================================================
APP_USER="notesapp"
APP_DIR="/opt/notesapp"
APP_REPO="https://github.com/mosesekerin/cloud-system-evolution.git"
APP_ENTRY="server.js"
APP_LOG="/var/log/notesapp.log"
APP_DATA="${APP_DIR}/notes.json"
SERVICE_NAME="notesapp"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
NODE_BIN="/usr/bin/node"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# =============================================================================
# SECTION 1: SYSTEM PREPARATION
# =============================================================================
log "==> [1/9] Updating system packages..."
sudo dnf update -y

log "==> [1/9] Installing required dependencies: git, nodejs..."
sudo dnf install -y git nodejs

# Validate Node.js installation
if ! command -v node &>/dev/null; then
    log "ERROR: Node.js installation failed. Aborting."
    exit 1
fi
log "Node.js version: $(node --version)"
log "npm version: $(npm --version)"

# =============================================================================
# SECTION 2: USER ISOLATION
# =============================================================================
log "==> [2/9] Creating system user '${APP_USER}'..."
if ! id "${APP_USER}" &>/dev/null; then
    sudo useradd \
        --system \
        --create-home \
        --home-dir "/home/${APP_USER}" \
        --shell /sbin/nologin \
        "${APP_USER}"
    log "User '${APP_USER}' created."
else
    log "User '${APP_USER}' already exists. Skipping creation."
fi

# =============================================================================
# SECTION 3: APPLICATION DEPLOYMENT
# =============================================================================
log "==> [3/9] Deploying application to ${APP_DIR}..."

# Create application directory idempotently
sudo mkdir -p "${APP_DIR}"

# Clone or update the repository
if [ -d "${APP_DIR}/.git" ]; then
    log "Repository already exists. Pulling latest changes..."
    sudo -u "${APP_USER}" git -C "${APP_DIR}" pull origin || {
        log "ERROR: git pull failed. Aborting."
        exit 1
    }
else
    log "Cloning repository..."
    # Clone into a temp location then move to avoid partial-clone issues
    TMPDIR=$(mktemp -d)
    git clone "${APP_REPO}" "${TMPDIR}/repo" || {
        log "ERROR: Repository clone failed. Aborting."
        rm -rf "${TMPDIR}"
        exit 1
    }
    sudo cp -a "${TMPDIR}/repo/." "${APP_DIR}/"
    rm -rf "${TMPDIR}"
fi

# Ensure ownership belongs to notesapp
sudo chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
sudo chmod 750 "${APP_DIR}"
log "Application deployed to ${APP_DIR}."

# =============================================================================
# SECTION 4: DEPENDENCY INSTALLATION
# =============================================================================
log "==> [4/9] Installing Node.js production dependencies..."
sudo -u "${APP_USER}" bash -c "cd ${APP_DIR} && npm install --omit=dev" || {
    log "ERROR: npm install failed. Aborting."
    exit 1
}
log "npm dependencies installed successfully."

# =============================================================================
# SECTION 5: PERSISTENCE SETUP
# =============================================================================
log "==> [5/9] Setting up application data persistence..."
if [ ! -f "${APP_DATA}" ]; then
    echo "[]" | sudo tee "${APP_DATA}" > /dev/null
    log "Created ${APP_DATA} with empty JSON array."
else
    log "${APP_DATA} already exists. Skipping creation."
fi
sudo chown "${APP_USER}:${APP_USER}" "${APP_DATA}"
sudo chmod 640 "${APP_DATA}"

# =============================================================================
# SECTION 6: LOGGING SETUP
# =============================================================================
log "==> [6/9] Setting up application log file..."
if [ ! -f "${APP_LOG}" ]; then
    sudo touch "${APP_LOG}"
    log "Created ${APP_LOG}."
else
    log "${APP_LOG} already exists. Skipping creation."
fi
sudo chown "${APP_USER}:${APP_USER}" "${APP_LOG}"
sudo chmod 640 "${APP_LOG}"

# =============================================================================
# SECTION 7: SYSTEMD SERVICE MANAGEMENT
# =============================================================================
log "==> [7/9] Creating systemd service unit: ${SERVICE_FILE}..."

sudo tee "${SERVICE_FILE}" > /dev/null <<EOF
[Unit]
Description=Notes Application - Node.js Express Service
Documentation=https://github.com/mosesekerin/cloud-system-evolution
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${NODE_BIN} ${APP_DIR}/${APP_ENTRY}
Restart=on-failure
RestartSec=5s
StandardOutput=append:${APP_LOG}
StandardError=append:${APP_LOG}

# Environment
Environment=NODE_ENV=production

# Security Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 "${SERVICE_FILE}"
log "Systemd service unit written to ${SERVICE_FILE}."

# =============================================================================
# SECTION 8: LIFECYCLE ENABLEMENT
# =============================================================================
log "==> [8/9] Reloading systemd daemon..."
sudo systemctl daemon-reload

log "Enabling ${SERVICE_NAME} service to start on boot..."
sudo systemctl enable "${SERVICE_NAME}"

# Handle already-running service for idempotent reruns
if sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "Service '${SERVICE_NAME}' is already running. Restarting to apply changes..."
    sudo systemctl restart "${SERVICE_NAME}"
else
    log "Starting ${SERVICE_NAME} service..."
    sudo systemctl start "${SERVICE_NAME}"
fi

# =============================================================================
# SECTION 9: VALIDATION
# =============================================================================
log "==> [9/9] Validating service startup..."

# Allow a moment for the service to initialise
sleep 3

if sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "SUCCESS: Service '${SERVICE_NAME}' is active and running."
else
    log "ERROR: Service '${SERVICE_NAME}' failed to start. Dumping journal..."
    sudo journalctl -u "${SERVICE_NAME}" --no-pager -n 50
    exit 1
fi

log "Service status:"
sudo systemctl status "${SERVICE_NAME}" --no-pager

# =============================================================================
# PROVISIONING COMPLETE
# =============================================================================
log "============================================================"
log " Provisioning complete."
log " Application : ${APP_DIR}/${APP_ENTRY}"
log " Data file   : ${APP_DATA}"
log " Log file    : ${APP_LOG}"
log " Service     : systemctl status ${SERVICE_NAME}"
log "============================================================"
