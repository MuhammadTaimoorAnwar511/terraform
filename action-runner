#!/usr/bin/env bash
# =============================================================================
# GitHub Actions self-hosted runner installer
# =============================================================================

set -u -o pipefail
STEP="Initialization"
error_handler() {
    echo "❌ Error during: $STEP" >&2
    exit 1
}
trap error_handler ERR

# ─── Configuration ───────────────────────────────────────────────────────────
FOLDER_NAME=""
ARCHITECTURE="x64"  # Options: x64, ARM, ARM64

# Replace this with your actual config command:
GITHUB_CONFIGURE="" #"./config.sh --url --token YOUR_TOKEN"

# ─── Create Runner Directory ─────────────────────────────────────────────────
STEP="Creating runner directory"
RUNNER_DIR="actions-runner_${FOLDER_NAME}"
mkdir -p "${RUNNER_DIR}" && cd "${RUNNER_DIR}"
echo "✔️ Created and moved into ${RUNNER_DIR}"

# ─── Select Platform and Download ────────────────────────────────────────────
TARBALL=""
CHECKSUM=""

if [[ "$ARCHITECTURE" == "x64" ]]; then
    TARBALL="actions-runner-linux-x64-2.326.0.tar.gz"
    CHECKSUM="9c74af9b4352bbc99aecc7353b47bcdfcd1b2a0f6d15af54a99f54a0c14a1de8"
elif [[ "$ARCHITECTURE" == "ARM" ]]; then
    TARBALL="actions-runner-linux-arm-2.326.0.tar.gz"
    CHECKSUM="e71a8e88b0ad4d05e315a42de9aef13ed3eb7a8ac37f4693cbeaba4ac353ff30"
elif [[ "$ARCHITECTURE" == "ARM64" ]]; then
    TARBALL="actions-runner-linux-arm64-2.326.0.tar.gz"
    CHECKSUM="ee7c229c979c5152e9f12be16ee9e83ff74c9d9b95c3c1aeb2e9b6d07157ec85"
else
    echo "❌ Unsupported architecture: $ARCHITECTURE"
    exit 1
fi

STEP="Downloading runner tarball"
curl -o "$TARBALL" -L "https://github.com/actions/runner/releases/download/v2.326.0/${TARBALL}"
echo "✔️ Downloaded $TARBALL"

STEP="Verifying checksum"
echo "${CHECKSUM}  ${TARBALL}" | shasum -a 256 -c -
echo "✔️ Checksum passed"

STEP="Extracting runner"
tar xzf "./${TARBALL}"
echo "✔️ Extracted $TARBALL"

# ─── Configure GitHub Runner ─────────────────────────────────────────────────
STEP="Configuring GitHub Runner"

if [[ -z "$GITHUB_CONFIGURE" ]]; then
    echo "❌ GITHUB_CONFIGURE variable is empty. Please set it."
    exit 1
fi

eval "${GITHUB_CONFIGURE}"

# ─── Install and Start as Service ────────────────────────────────────────────
STEP="Installing runner service"
sudo ./svc.sh install
echo "✔️ Service installed"

STEP="Starting runner service"
sudo ./svc.sh start
echo "✔️ Service started"
