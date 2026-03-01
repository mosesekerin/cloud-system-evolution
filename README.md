

# 📘 NotesApp Deployment on Amazon Linux (EC2)

This guide provisions and runs the NotesApp as a managed Linux service using **systemd** on Amazon Linux 2023.

All commands assume you are using a default EC2 user (non-root) with `sudo`.

---

## 1. Update System

```bash
sudo dnf update -y
```

---

## 2. Install Required Packages

```bash
sudo dnf install -y git nodejs
```

Verify installation:

```bash
node -v
npm -v
```

---

## 3. Create Dedicated Service User

```bash
sudo useradd --system --create-home --shell /sbin/nologin notesapp || true
```

Why:

* Runs app securely
* Provides npm cache directory

---

## 4. Create Application Directory

```bash
sudo mkdir -p /opt/notesapp
sudo chown notesapp:notesapp /opt/notesapp
```

---

## 5. Deploy Application

```bash
sudo git clone https://github.com/mosesekerin/cloud-system-evolution.git /opt/notesapp
sudo chown -R notesapp:notesapp /opt/notesapp
```

---

## 6. Install App Dependencies (as service user)

```bash
cd /opt/notesapp
sudo -u notesapp npm install --omit=dev
```

---

## 7. Prepare Persistent Storage

```bash
sudo touch /opt/notesapp/notes.json
sudo chown notesapp:notesapp /opt/notesapp/notes.json
```

---

## 8. Prepare Log File

```bash
sudo touch /var/log/notesapp.log
sudo chown notesapp:notesapp /var/log/notesapp.log
```

---

## 9. Create systemd Service

```bash
sudo tee /etc/systemd/system/notesapp.service > /dev/null <<EOF
[Unit]
Description=Notes App (Express.js)
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/notesapp/server.js
WorkingDirectory=/opt/notesapp
Restart=always
RestartSec=5
User=notesapp
Group=notesapp
Environment=NODE_ENV=production

StandardOutput=append:/var/log/notesapp.log
StandardError=append:/var/log/notesapp.log

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
```

---

## 10. Reload systemd

```bash
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
```

---

## 11. Start Service

```bash
sudo systemctl start notesapp
```

Check status:

```bash
sudo systemctl status notesapp
```

---

## 12. Enable Boot Startup

```bash
sudo systemctl enable notesapp
```

---

## 13. Verify Logging

```bash
tail -f /var/log/notesapp.log
```

---

# 🧪 Validation Tests

### Confirm service is running:

```bash
sudo systemctl is-active notesapp
```

### Confirm Node process exists:

```bash
sudo ss -tulnp | grep node
```

---

# 🔁 Operational Commands

Restart:

```bash
sudo systemctl restart notesapp
```

Stop:

```bash
sudo systemctl stop notesapp
```

Disable boot:

```bash
sudo systemctl disable notesapp
```

---

# 📦 Outcome

After completing this setup:

✔ App runs as a managed Linux service
✔ Automatically restarts on crash
✔ Starts on system boot
✔ Runs as non-root
✔ Logs to `/var/log/notesapp.log`
✔ Persists notes to disk

---

# ⚠️ Important Note

This guide assumes you are executing as a non-root EC2 user with `sudo`.

All privileged operations are explicitly prefixed.