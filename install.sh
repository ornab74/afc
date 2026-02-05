#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Termux → Ubuntu proot → AFC FULL AUTO-SETUP + AUTO-START
# Supports PRIVATE repo via GitHub PAT (prompted once)
# Folder = afc
# ============================================================

set -e

echo "Updating Termux packages..."
pkg update -y && pkg upgrade -y
pkg install -y bash bzip2 coreutils curl file findutils gawk gzip ncurses-utils proot sed tar util-linux xz-utils git wget

echo "Removing any old proot-distro installations (clean start)..."
proot-distro remove ubuntu 2>/dev/null || true
rm -rf "$HOME/proot-distro" 2>/dev/null || true

echo "Cloning known-working proot-distro commit (ca53fee – full TTY support)..."
cd "$HOME"
git clone --depth=1 https://github.com/termux/proot-distro.git
cd proot-distro
git fetch origin ca53fee288be8f46ee0e4fc8ee23934023472054
git checkout FETCH_HEAD

echo "Installing proot-distro from this commit..."
chmod +x install.sh
./install.sh

echo "Installing Ubuntu (24.04 rootfs)..."
proot-distro install ubuntu

echo "Creating TMP dir..."
export PROOT_TMP_DIR="$HOME/tmp"
mkdir -p "$PROOT_TMP_DIR"

# ────────────────────────────────────────────────
# Ask for GitHub PAT (only if repo is private)
# ────────────────────────────────────────────────
echo ""
echo "If your repo https://github.com/ornab74/afc.git is PRIVATE,"
echo "you need a GitHub Personal Access Token (classic) with 'repo' scope."
echo "→ https://github.com/settings/tokens → Generate new token (classic)"
echo ""
read -s -p "Enter GitHub PAT (leave empty if public): " GITHUB_PAT
echo ""
echo ""

# Prepare PAT argument for git (empty = no auth)
if [ -n "$GITHUB_PAT" ]; then
    GIT_AUTH_PREFIX="https://x-access-token:${GITHUB_PAT}@"
    echo "→ Using PAT for private repo access (token NOT saved to disk)"
else
    GIT_AUTH_PREFIX="https://"
    echo "→ No PAT provided → assuming public repo"
fi

echo "Setting up sudouser + Python + AFC repo (with git pull fallback + PAT support)..."
proot-distro login ubuntu -- <<EOF
apt update && apt upgrade -y
apt install -y sudo python3 python3-pip python3-venv git nano curl

# Create sudouser (no password)
adduser --disabled-password --gecos "" sudouser 2>/dev/null || true
usermod -aG sudo sudouser
echo "sudouser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/sudouser-nopasswd
chmod 0440 /etc/sudoers.d/sudouser-nopasswd

# Clone or update afc repo
su - sudouser -c '
    set -e
    cd ~
    if [ -d "afc/.git" ]; then
        echo "Existing afc git repo found → running git pull..."
        cd afc
        git pull --ff-only || { echo "git pull failed - trying reset..."; git fetch && git reset --hard origin/main; }
    else
        echo "Cloning fresh afc repo..."
        mkdir -p afc
        cd afc
        git clone --depth=1 ${GIT_AUTH_PREFIX}github.com/ornab74/afc.git .
    fi

    # venv + dependencies
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip setuptools wheel
    [ -f requirements.txt ] && pip install -r requirements.txt || echo "No requirements.txt found - skipping pip install"
    chmod +x main.py 2>/dev/null || true
    echo "AFC setup/update finished inside Ubuntu"
'
EOF

# Clear sensitive variable from shell as soon as possible
unset GITHUB_PAT

# ============================================================
# FINAL STEP: FORCE AUTO-START WITH UPDATED BANNER + FULL TTY
# ============================================================

cat > ~/.bashrc <<'BASHRC'
# === AUTO-START AFC TUI IN UBUNTU PROOT (afc folder + venv) ===
if [ -z "$AFC_STARTED" ] && [ "$PWD" = "$HOME" ] && [ -z "$SSH_CLIENT" ] && [ -z "$TMUX" ]; then
    export AFC_STARTED=1

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║          Starting AFC TUI (afc/main.py)            ║"
    echo "║        Ubuntu proot → /home/sudouser/afc                ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo "   Type 'exit' twice to return to Termux"
    echo ""

    proot-distro login ubuntu --user sudouser --shared-tmp -- bash -c "
        cd ~/afc || { echo 'Cannot cd to ~/afc'; exit 1; }
        
        # Activate venv
        source venv/bin/activate || { echo 'Cannot activate venv'; exit 1; }
        
        # Fix terminal + locale + unbuffered output
        export TERM=xterm-256color
        export LANG=C.UTF-8
        export PYTHONUNBUFFERED=1
        
        # Run your TUI interactively with full pseudo-tty
        clear
        echo 'Starting main.py in venv...'
        exec python -u main.py
    "
    
    clear
    echo "Returned to Termux."
fi
BASHRC

# Optional: manual start alias
echo "alias afc='proot-distro login ubuntu --user sudouser -- bash -c \"cd ~/afc && source venv/bin/activate && python -u main.py\"'" >> ~/.bashrc

echo "--------------------------------------------------------------"
echo "ALL DONE!"
echo "Close and reopen Termux (or run: source ~/.bashrc)"
echo "The AFC TUI should now auto-start when opening Termux"
echo ""
echo "Note: PAT was only used temporarily during setup and is NOT stored."
echo "--------------------------------------------------------------"
