#!/usr/bin/env bash
set -euo pipefail

SRC="${HOME}/from_pod/specedge"
DST="${HOME}/specedge"

echo "[1/4] Source: ${SRC}"
echo "[2/4] Target: ${DST}"

if [ ! -d "${SRC}" ]; then
  echo "ERROR: source directory does not exist: ${SRC}"
  exit 1
fi

if [ ! -d "${DST}" ]; then
  echo "ERROR: target directory does not exist: ${DST}"
  exit 1
fi

echo "[3/4] Dry-run first..."
rsync -azni --delete --omit-dir-times \
  --exclude ".git/" \
  "${SRC}/" \
  "${DST}/"

echo
echo "上面是预演结果，没有真正同步。"
echo "确认没问题后输入 yes 继续真正同步："
read -r confirm

if [ "${confirm}" != "yes" ]; then
  echo "Canceled."
  exit 0
fi

echo "[4/4] Syncing for real..."

rsync -azi --delete --omit-dir-times \
  --exclude ".git/" \
  "${SRC}/" \
  "${DST}/"

echo "Done."