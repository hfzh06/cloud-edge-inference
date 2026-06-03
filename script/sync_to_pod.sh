#!/usr/bin/env bash
set -euo pipefail

# =========================
# 需要你按实际情况修改
# =========================
NAMESPACE="dev-zhaihanfeng"
POD_NAME="test-master-0"

# 如果你的 Pod 里只有一个 container，这里可以留空
# 如果有多个 container，填容器名，比如 CONTAINER_NAME="master"
CONTAINER_NAME=""

# 本地项目目录：默认取当前脚本所在目录的上一级
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 容器里的项目目录，也就是 PVC 挂载后的代码目录
REMOTE_DIR="/workspace/specedge"

# =========================
# 检查
# =========================
echo "[1/5] Local dir: ${LOCAL_DIR}"
echo "[2/5] Remote: ${NAMESPACE}/${POD_NAME}:${REMOTE_DIR}"

kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" >/dev/null

# =========================
# 组装 kubectl exec 参数
# =========================
if [[ -n "${CONTAINER_NAME}" ]]; then
  KUBECTL_EXEC_BASE=(kubectl exec -i -n "${NAMESPACE}" "${POD_NAME}" -c "${CONTAINER_NAME}" --)
  KUBECTL_EXEC_TTY=(kubectl exec -it -n "${NAMESPACE}" "${POD_NAME}" -c "${CONTAINER_NAME}" --)
else
  KUBECTL_EXEC_BASE=(kubectl exec -i -n "${NAMESPACE}" "${POD_NAME}" --)
  KUBECTL_EXEC_TTY=(kubectl exec -it -n "${NAMESPACE}" "${POD_NAME}" --)
fi

# =========================
# 确保远端目录存在
# =========================
echo "[3/5] Checking workspace mount and creating remote dir..."

"${KUBECTL_EXEC_BASE[@]}" sh -lc "
  echo 'Remote df:'
  df -h /workspace

  if [ ! -d /workspace ]; then
    echo 'ERROR: /workspace does not exist'
    exit 1
  fi

  mkdir -p '${REMOTE_DIR}'
"

# =========================
# 检查远端是否有 rsync
# 如果镜像里已经装了 rsync，这一步会直接通过
# =========================
echo "[4/5] Checking rsync in container..."
if ! "${KUBECTL_EXEC_BASE[@]}" sh -lc 'command -v rsync >/dev/null 2>&1'; then
  echo "Container does not have rsync."
  echo "Please install rsync in your Dockerfile:"
  echo "  apt-get update && apt-get install -y rsync"
  exit 1
fi

# =========================
# 创建 rsync 通过 kubectl exec 连接 Pod 的 wrapper
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

rsync -az --delete --blocking-io --itemize-changes -n \
  -e "${KUBE_RSH}" \
  --exclude ".git/" \
  --exclude ".idea/" \
  --exclude ".vscode/" \
  --exclude "__pycache__/" \
  --exclude ".pytest_cache/" \
  --exclude ".mypy_cache/" \
  --exclude ".ruff_cache/" \
  --exclude ".venv/" \
  --exclude "venv/" \
  --exclude "node_modules/" \
  --exclude "logs/" \
  --exclude "outputs/" \
  --exclude ".env" \
  "${LOCAL_DIR}/" \
  "${POD_NAME}:${REMOTE_DIR}/"

read -r -p "Proceed with actual sync? (y/N): " confirm_sync
if [[ ! "${confirm_sync}" =~ ^[Yy]$ ]]; then
  echo "Sync canceled."
  exit 0
fi

echo "Syncing..."

rsync -az --delete --blocking-io --itemize-changes \
  -e "${KUBE_RSH}" \
  --exclude ".git/" \
  --exclude ".idea/" \
  --exclude ".vscode/" \
  --exclude "__pycache__/" \
  --exclude ".pytest_cache/" \
  --exclude ".mypy_cache/" \
  --exclude ".ruff_cache/" \
  --exclude ".venv/" \
  --exclude "venv/" \
  --exclude "node_modules/" \
  --exclude "logs/" \
  --exclude "outputs/" \
  --exclude ".env" \
  "${LOCAL_DIR}/" \
  "${POD_NAME}:${REMOTE_DIR}/"

echo
echo "Sync finished."
echo "Remote path: ${POD_NAME}:${REMOTE_DIR}"
echo
echo "You can enter container with:"
if [[ -n "${CONTAINER_NAME}" ]]; then
  echo "kubectl exec -it -n ${NAMESPACE} ${POD_NAME} -c ${CONTAINER_NAME} -- bash"
else
  echo "kubectl exec -it -n ${NAMESPACE} ${POD_NAME} -- bash"
fi