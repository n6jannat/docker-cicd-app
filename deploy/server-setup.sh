#!/usr/bin/env bash
# One-time server preparation for docker-cicd-app deployments.
#
# Usage (as root or with sudo):
#   curl -fsSL https://raw.githubusercontent.com/n6jannat/docker-cicd-app/main/deploy/server-setup.sh | sudo bash
#   # or: sudo DEPLOY_USER=myuser bash server-setup.sh
#
# What it does:
#   1. Installs curl, Docker Engine and the Docker Compose plugin
#   2. Creates the deploy user (default: "deploy") and adds it to the docker group
#   3. Generates an SSH key pair for GitHub Actions and authorizes it for that user
#   4. Prints the values to paste into GitHub (DEPLOY_HOST, DEPLOY_USER, DEPLOY_SSH_KEY)
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
KEY_NAME="github-actions-deploy"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (use sudo)." >&2
  exit 1
fi

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ---- 1. curl -------------------------------------------------------------
log "Installing curl"
if command -v apt-get >/dev/null; then
  apt-get update -y
  apt-get install -y curl ca-certificates
elif command -v dnf >/dev/null; then
  dnf install -y curl ca-certificates
elif command -v yum >/dev/null; then
  yum install -y curl ca-certificates
else
  command -v curl >/dev/null || { echo "Install curl manually, then re-run." >&2; exit 1; }
fi

# ---- 2. Docker Engine + compose plugin ------------------------------------
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  log "Docker and compose plugin already installed"
else
  log "Installing Docker Engine + compose plugin (official get.docker.com script)"
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
docker --version
docker compose version

# ---- 3. Deploy user with docker permissions -------------------------------
if id "$DEPLOY_USER" >/dev/null 2>&1; then
  log "User '$DEPLOY_USER' already exists"
else
  log "Creating user '$DEPLOY_USER'"
  useradd --create-home --shell /bin/bash "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"
log "'$DEPLOY_USER' added to the docker group"

# ---- 4. SSH key for GitHub Actions ----------------------------------------
HOME_DIR="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
SSH_DIR="$HOME_DIR/.ssh"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$SSH_DIR"
if [[ ! -f "$SSH_DIR/$KEY_NAME" ]]; then
  log "Generating SSH key for GitHub Actions"
  ssh-keygen -t ed25519 -N "" -C "$KEY_NAME" -f "$SSH_DIR/$KEY_NAME" >/dev/null
fi
touch "$SSH_DIR/authorized_keys"
grep -qxF "$(cat "$SSH_DIR/$KEY_NAME.pub")" "$SSH_DIR/authorized_keys" \
  || cat "$SSH_DIR/$KEY_NAME.pub" >> "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys" "$SSH_DIR/$KEY_NAME"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$SSH_DIR"

# ---- 5. Verify -------------------------------------------------------------
log "Verifying '$DEPLOY_USER' can run docker without sudo"
su - "$DEPLOY_USER" -c "docker ps >/dev/null && docker compose version >/dev/null && curl --version >/dev/null" \
  && echo "OK"

PUBLIC_IP="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

cat <<MSG

==========================================================================
 Server ready. Add these in GitHub:
   Repo -> Settings -> Environments -> staging (and production)

 Secrets:
   DEPLOY_HOST     = ${PUBLIC_IP}
   DEPLOY_USER     = ${DEPLOY_USER}
   DEPLOY_SSH_KEY  = (the full private key below, including BEGIN/END lines)

 Variables:
   HOST_PORT       = 3000            (e.g. 3001 for staging, 80 for production)
   APP_URL         = http://${PUBLIC_IP}:3000

 Make sure the firewall allows SSH (22) and HOST_PORT.
==========================================================================
MSG
echo "----- DEPLOY_SSH_KEY (copy everything between the dashed lines) -----"
cat "$SSH_DIR/$KEY_NAME"
echo "---------------------------------------------------------------------"
echo "Tip: after copying the key into GitHub you can delete the private key file:"
echo "  sudo rm $SSH_DIR/$KEY_NAME"
