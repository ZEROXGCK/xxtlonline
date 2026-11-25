#!/usr/bin/env bash
# =====================================================================
#  setup.sh — เมนูติดตั้งรวม (Ubuntu 22.04/24.04, Debian ที่ใช้ apt + systemd)
#
#  วางไฟล์นี้ไว้โฟลเดอร์เดียวกับไฟล์ zip ทั้งสอง แล้วรัน:
#      sudo bash setup.sh
#
#  หรือสั่งบรรทัดเดียว (โหลด zip จาก GitHub ให้เอง):
#      curl -fsSL https://raw.githubusercontent.com/ZEROXGCK/xxtlonline/main/setup.sh | sudo bash
#
#  เมนู:
#      1) ติดตั้ง wselx        (เว็บร้านค้า + บอท)
#      2) ติดตั้ง xxtlonline    (SSH WebSocket + แดชบอร์ด)
#      0) ออก
#
#  รันตรงโดยไม่ผ่านเมนู:   sudo bash setup.sh 1
#                          sudo bash setup.sh 2 --domain panel.example.com --email me@x.com
#  (อาร์กิวเมนต์หลังเลขเมนูจะส่งต่อให้สคริปต์ติดตั้งของตัวนั้น)
#
#  ตัวแปรที่ตั้งเองได้:
#      WSELX_ZIP / XXTL_ZIP   path ของไฟล์ zip (ไม่ตั้ง = หา wselx*.zip / xxtlonline*.zip ข้างสคริปต์)
#      WSELX_SRC              path โฟลเดอร์ซอร์สถาวร (ค่าเริ่มต้น /opt/wselx-src)
#      และตัวแปรของ wselx: DOMAIN, EMAIL, ADMIN_USERNAME, ADMIN_PASSWORD, APP_DIR
# =====================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WSELX_SRC="${WSELX_SRC:-/opt/wselx-src}"
# ที่เก็บบน GitHub (ใช้ตอนไม่มี zip ในเครื่อง เช่นสั่งผ่าน curl | bash)
GH_REPO="${GH_REPO:-ZEROXGCK/xxtlonline}"
GH_BRANCH="${GH_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/$GH_REPO/$GH_BRANCH"
WSELX_REMOTE_ZIP="${WSELX_REMOTE_ZIP:-wselx-sell.zip}"
XXTL_REMOTE_ZIP="${XXTL_REMOTE_ZIP:-xxtlonline_panel.zip}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "ต้องรันด้วย root — ใช้: sudo bash setup.sh"
command -v apt-get >/dev/null || die "รองรับเฉพาะ Ubuntu/Debian (apt)"

# ---------- ช่วยหาและแตกไฟล์ต้นทาง ----------
# find_src <ชื่อโฟลเดอร์> <ตัวแปร zip> <pattern zip> <ไฟล์ที่ต้องมีเพื่อยืนยัน> <ชื่อ zip บน GitHub>
# พิมพ์ path โฟลเดอร์ซอร์สที่พร้อมใช้ (แตกใน $WORK ถ้าเป็น zip)
find_src() {
  local name="$1" zipvar="$2" pattern="$3" marker="$4" remote="${5:-}" zip="" d
  zip="${!zipvar:-}"
  # 1) โฟลเดอร์ที่แตกไว้แล้วข้างสคริปต์
  for d in "$HERE/$name" "$PWD/$name"; do
    [ -f "$d/$marker" ] && { echo "$d"; return 0; }
  done
  # 2) zip ที่ระบุ หรือ zip ล่าสุดที่ตรงกับ pattern
  if [ -z "$zip" ]; then
    zip="$(ls -1t "$HERE"/$pattern "$PWD"/$pattern 2>/dev/null | head -n1 || true)"
  fi
  # 3) ไม่มีในเครื่อง → โหลดจาก GitHub
  if [ -z "$zip" ] || [ ! -f "$zip" ]; then
    [ -n "$remote" ] || return 1
    command -v curl >/dev/null || { apt-get update -qq; apt-get install -y -qq curl ca-certificates >/dev/null; }
    zip="$WORK/$remote"
    echo "ไม่พบ zip ในเครื่อง — ดาวน์โหลด $RAW_BASE/$remote" >&2
    curl -fsSL "$RAW_BASE/$remote" -o "$zip" || { echo "โหลดไม่สำเร็จ (repo ต้องเป็น public และชื่อไฟล์ต้องตรง)" >&2; return 1; }
  fi
  command -v unzip >/dev/null || { apt-get update -qq; apt-get install -y -qq unzip >/dev/null; }
  local out="$WORK/$name"; mkdir -p "$out"
  unzip -oq "$zip" -d "$out"
  # รองรับทั้ง zip ที่มีโฟลเดอร์ชั้นนอกและไม่มี
  if [ -f "$out/$name/$marker" ]; then echo "$out/$name"
  elif [ -f "$out/$marker" ]; then echo "$out"
  else return 1; fi
}

# ---------- 1) wselx ----------
install_wselx() {
  say "ติดตั้ง wselx"
  local src
  src="$(find_src wselx WSELX_ZIP 'wselx*.zip' server.js "$WSELX_REMOTE_ZIP")" \
    || die "หา/โหลด wselx ไม่สำเร็จ — เช็กชื่อ zip บน GitHub (WSELX_REMOTE_ZIP) หรือตั้ง WSELX_ZIP=/path/file.zip"
  echo "ซอร์ส: $src"

  # install.sh ของ wselx ดึงโค้ดจาก git → ทำ repo ในเครื่องให้ จะได้ไม่ต้องใช้ GitHub
  # รันซ้ำด้วย zip เวอร์ชันใหม่ = อัปเดต (ไม่แตะ .env / ฐานข้อมูล)
  command -v git >/dev/null || { apt-get update -qq; apt-get install -y -qq git >/dev/null; }
  mkdir -p "$WSELX_SRC"
  if [ ! -d "$WSELX_SRC/.git" ]; then git -C "$WSELX_SRC" init -q -b main; fi
  # ล้างไฟล์เดิมในซอร์ส (ยกเว้น .git) แล้วคัดลอกเวอร์ชันใหม่ทับ
  find "$WSELX_SRC" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  cp -a "$src"/. "$WSELX_SRC"/
  git -C "$WSELX_SRC" add -A
  git -C "$WSELX_SRC" -c user.name=setup -c user.email=setup@localhost \
      commit -qm "wselx $(date +%F-%H%M)" 2>/dev/null || true

  # ถ้ามี REPO_URL ของตัวเองอยู่แล้ว (เช่น GitHub) ให้ใช้อันนั้นแทน
  REPO_URL="${REPO_URL:-$WSELX_SRC}" BRANCH="${BRANCH:-main}" \
    bash "$WSELX_SRC/install.sh" "$@"
}

# ---------- 2) xxtlonline ----------
install_xxtl() {
  say "ติดตั้ง xxtlonline"
  local src
  src="$(find_src xxtlonline XXTL_ZIP 'xxtlonline*.zip' install.sh "$XXTL_REMOTE_ZIP")" \
    || die "หา/โหลด xxtlonline ไม่สำเร็จ — เช็กชื่อ zip บน GitHub (XXTL_REMOTE_ZIP) หรือตั้ง XXTL_ZIP=/path/file.zip"
  echo "ซอร์ส: $src"
  # แก้บั๊กใน install.sh: บรรทัดหา SSH port ใช้ pipe ร่วมกับ set -e/pipefail ถ้า sshd -T ล้มเหลว
  # หรือโดน SIGPIPE สคริปต์จะหยุดเงียบๆ ที่ขั้น [5/6] firewall (แก้ซ้ำได้ปลอดภัย)
  sed -i "s#awk '/^port /{print \$2; exit}')#awk '/^port /{print \$2; exit}' || true)#" "$src/install.sh"
  # ติดตั้งจากไฟล์ในเครื่องโดยตรง (ไม่ดึงจาก GitHub) — ต้องรันจาก path จริงเพื่อให้สคริปต์หา src/ เจอ
  bash "$src/install.sh" "$@"
}

# ---------- เมนู ----------
choice="${1:-}"
if [ -n "$choice" ]; then shift; fi

if [ -z "$choice" ]; then
  [ -r /dev/tty ] || die "ไม่มีเทอร์มินัลให้ถาม — ระบุเลขเมนู เช่น: sudo bash setup.sh 1"
  cat <<'MENU'

  ============================================
    เมนูติดตั้ง
  ============================================
    1) ติดตั้ง wselx        (เว็บร้านค้า + บอท)
    2) ติดตั้ง xxtlonline    (SSH WebSocket + แดชบอร์ด)
    0) ออก
  ============================================
MENU
  read -r -p "เลือก [1/2/0]: " choice </dev/tty || true
fi

case "$choice" in
  1) install_wselx "$@" ;;
  2) install_xxtl  "$@" ;;
  0|q|"") echo "ออกแล้ว"; exit 0 ;;
  *) die "ไม่รู้จักตัวเลือก: $choice (ใช้ 1, 2 หรือ 0)" ;;
esac
