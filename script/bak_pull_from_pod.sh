#!/usr/bin/env bash
set -euo pipefail

# =========================
# 基本配置
# =========================
NAMESPACE="dev-zhaihanfeng"
POD_NAME="test-master-0"

# 如果 Pod 里只有一个 container，留空即可
CONTAINER_NAME=""

# 容器里的项目目录
REMOTE_DIR="/workspace/specedge"

# 本地接收目录
# 安全起见，默认先拉到 ~/from_pod/specedge，不直接覆盖本地项目
LOCAL_DIR="${HOME}/from_pod/specedge"

# =========================
# 打印信息
# =========================
echo "[1/5] Remote: ${NAMESPACE}/${POD_NAME}:${REMOTE_DIR}"
echo "[2/5] Local:  ${LOCAL_DIR}"

kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" >/dev/null

mkdir -p "${LOCAL_DIR}"

# =========================
# 检查远端目录
# =========================
echo "[3/5] Checking remote dir..."

if [[ -n "${CONTAINER_NAME}" ]]; then
  KUBECTL_EXEC_BASE=(kubectl exec -i -n "${NAMESPACE}" "${POD_NAME}" -c "${CONTAINER_NAME}" --)
else
  KUBECTL_EXEC_BASE=(kubectl exec -i -n "${NAMESPACE}" "${POD_NAME}" --)
fi

"${KUBECTL_EXEC_BASE[@]}" sh -lc "
  if [ ! -d '${REMOTE_DIR}' ]; then
    echo 'ERROR: remote dir does not exist: ${REMOTE_DIR}'
    exit 1
  fi
  echo 'Remote dir exists: ${REMOTE_DIR}'
"

# =========================
# 检查容器里是否有 rsync
# =========================
echo "[4/5] Checking rsync in container..."

if ! "${KUBECTL_EXEC_BASE[@]}" sh -lc 'command -v rsync >/dev/null 2>&1'; then
  echo "ERROR: container does not have rsync."
  echo "Please install rsync in your image or container."
  exit 1
fi

# =========================
# 创建 kubectl exec wrapper
# =========================
KUBE_RSH="$(mktemp)"

cat > "${KUBE_RSH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

pod="\$1"
shift

if [[ -n "${CONTAINER_NAME}" ]]; then
  exec kubectl exec -i -n "${NAMESPACE}" "\${pod}" -c "${CONTAINER_NAME}" -- "\$@"
else
  exec kubectl exec -i -n "${NAMESPACE}" "\${pod}" -- "\$@"
fi
EOF

chmod +x "${KUBE_RSH}"

cleanup() {
  rm -f "${KUBE_RSH}"
}
trap cleanup EXIT

# =========================
# 预演并确认同步
# =========================
echo "[5/5] Dry-run preview (-n)..."

rsync -avzi --blocking-io -n \
  -e "${KUBE_RSH}" \
  --exclude "__pycache__/" \
  --exclude ".pytest_cache/" \
  --exclude ".mypy_cache/" \
  --exclude ".ruff_cache/" \
  --exclude ".venv/" \
  --exclude "venv/" \
  --exclude "node_modules/" \
  "${POD_NAME}:${REMOTE_DIR}/" \
  "${LOCAL_DIR}/"

read -r -p "Proceed with actual pull? (y/N): " confirm_pull
if [[ ! "${confirm_pull}" =~ ^[Yy]$ ]]; then
  echo "Pull canceled."
  exit 0
fi

echo "Pulling from pod to VM..."

rsync -avzi --blocking-io \
  -e "${KUBE_RSH}" \
  --exclude "__pycache__/" \
  --exclude ".pytest_cache/" \
  --exclude ".mypy_cache/" \
  --exclude ".ruff_cache/" \
  --exclude ".venv/" \
  --exclude "venv/" \
  --exclude "node_modules/" \
  "${POD_NAME}:${REMOTE_DIR}/" \
  "${LOCAL_DIR}/"

echo
echo "finished."
