#!/usr/bin/env bash
# =====================================================================
#  setup.sh — ติดตั้งอัตโนมัติ wselx (ร้านค้า) + xxtlonline (SSH WebSocket + แดชบอร์ด)
#             ถามแค่ "โดเมน" ข้อเดียว (Ubuntu 22.04/24.04, Debian ที่ใช้ apt + systemd)
#
#  วิธีใช้ (วางไฟล์นี้ไว้โฟลเดอร์เดียวกับ wselx-sell.zip และ xxtlonline_panel.zip):
#      sudo bash setup.sh                   # ถามโดเมน แล้วทำให้ทุกอย่าง
#      sudo bash setup.sh shop.example.com  # ถามแค่ชื่อผู้ใช้/รหัสแอดมิน (กด Enter ข้าม = admin + รหัสสุ่ม)
#      sudo bash setup.sh shop.example.com myuser 'MyPass123'   # ไม่ถามอะไรเลย
#  หรือสั่งบรรทัดเดียว (ต้องอัปโหลด xxtlonline_panel.zip + wselx-sell.zip ไว้ที่ /root/ ก่อน):
#      curl -fsSL https://raw.githubusercontent.com/ZEROXGCK/xxtlonline/main/setup.sh | sudo bash
#
#  ใช้ xxtlonline_panel.zip ตามเดิมทุกประการ (สคริปต์นี้ไม่แก้ไฟล์ใด ๆ ใน zip)
#  พอร์ต 22 = OpenSSH ของเครื่อง (ไม่ถูกย้าย/ไม่ถูกแย่ง)
#  ผลลัพธ์ (โดเมนเดียว): พอร์ต 80 = VPN (xxtlonline-ws ตามต้นฉบับ) / พอร์ต 443 = nginx สำหรับเว็บ:
#      https://โดเมน/         เว็บร้านค้า (wselx)
#      https://โดเมน/panel/   แดชบอร์ด xxtlonline
#      https://โดเมน/xui/     แผง 3x-ui (VLESS/VMess) — ติดตั้งให้ด้วย
#      พอร์ต 80               แอป VPN (NPV/NetMod/HTTP Custom: SSH + HTTP/WebSocket)
#      พอร์ต 443              เว็บเท่านั้น (ร้านค้า / แดชบอร์ด / 3x-ui) — ไม่ใช่ VPN
#      แอดมิน: ชื่อผู้ใช้/รหัสผ่านชุดเดียวกันทั้งร้านค้า แดชบอร์ด และ 3x-ui
#      ในหน้าแอดมินร้านค้า (เมนูเซิร์ฟเวอร์) มีปุ่ม "เชื่อมแดชบอร์ด" และ "เชื่อม 3x-ui" อัตโนมัติ
#
#  ตัวแปรที่ตั้งเองได้ (ไม่ตั้งก็ได้):
#      DOMAIN          โดเมน (แทนการพิมพ์ตอนถาม)
#      MODE            1 = ทั้งสอง (ติดตั้งแดชบอร์ดก่อน แล้วถามก่อนติดตั้งร้านค้าต่อ) | 2 = เฉพาะแดชบอร์ด VPN | 3 = เฉพาะร้านค้า
#                      (ไม่ตั้ง = สคริปต์ถามเอง)
#      YES=1           ตอบ "ใช่" ทุกคำถามอัตโนมัติ (ไม่หยุดถามระหว่างทาง)
#      ADMIN_USERNAME  ชื่อแอดมิน (ค่าเริ่มต้น admin)
#      ADMIN_PASSWORD  รหัสแอดมิน (ไม่ตั้ง = สุ่มให้ แสดงตอนจบ + เก็บใน /root/xxtl-wselx-info.txt)
#      EMAIL           อีเมลแจ้งเตือนใบรับรอง (ไม่ตั้ง = ไม่ใช้)
#      WSELX_ZIP / XXTL_ZIP   path ของ zip (ไม่ตั้ง = หาข้างสคริปต์; xxtlonline ไม่โหลดจาก GitHub เด็ดขาด)
#      SKIP_DNS_CHECK=1       ข้ามการตรวจ DNS (ไม่แนะนำ)
#      SKIP_3XUI=1            ไม่ติดตั้ง 3x-ui
#      SHOP_HTTPS_PORT พอร์ตร้านค้าตรง https://โดเมน:พอร์ต (ค่าเริ่มต้น 7778)
#      DASH_HTTPS_PORT พอร์ตแดชบอร์ดตรง https://โดเมน:พอร์ต (ค่าเริ่มต้น 6787)
# =====================================================================
set -Eeuo pipefail
# ถ้าสคริปต์หยุดกลางทาง ให้บอกว่าหยุดที่บรรทัดไหน/คำสั่งอะไร (ไม่หยุดเงียบ ๆ)
trap 'rc=$?; printf "\033[1;31m[x] สคริปต์หยุดที่บรรทัด %s (รหัส %s): %s\033[0m\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2' ERR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
WSELX_SRC="${WSELX_SRC:-/opt/wselx-src}"
APP_DIR="${APP_DIR:-/opt/wselx}"
GH_REPO="${GH_REPO:-ZEROXGCK/xxtlonline}"
GH_BRANCH="${GH_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/$GH_REPO/$GH_BRANCH"
WSELX_REMOTE_ZIP="${WSELX_REMOTE_ZIP:-wselx-sell.zip}"
DASH_HTTPS_PORT="${DASH_HTTPS_PORT:-6787}"   # เปิดแดชบอร์ดตรงที่ https://โดเมน:6787 ด้วย (นอกจาก /panel/)
SHOP_HTTPS_PORT="${SHOP_HTTPS_PORT:-7778}"   # เปิดร้านค้าตรงที่ https://โดเมน:7778 ด้วย (นอกจากพอร์ต 443)
XUI_PORT=2053           # พอร์ตแผง 3x-ui (ฟัง 127.0.0.1 เท่านั้น เข้าผ่าน https://โดเมน/xui/)
XUI_BASE=xui
XXTL_CONF=/etc/xxtlonline/xxtlonline.conf
INFO_FILE=/root/xxtl-wselx-info.txt
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

case "${1:-}" in -h|--help) sed -n '2,32p' "$0" 2>/dev/null || true; exit 0 ;; esac
[ "$(id -u)" -eq 0 ] || die "ต้องรันด้วย root — ใช้: sudo bash setup.sh"
command -v apt-get >/dev/null && command -v systemctl >/dev/null || die "รองรับเฉพาะ Ubuntu/Debian (apt + systemd)"
export DEBIAN_FRONTEND=noninteractive

# ถามใช่/ไม่ใช่ (ไม่มี tty หรือ YES=1 = ตอบค่าเริ่มต้นอัตโนมัติ)
ask_yn() {   # ask_yn "คำถาม" [y|n]  → คืน 0 = ใช่, 1 = ไม่
  local q="$1" d="${2:-y}" a="" hint="[Y/n]"
  [ "$d" = n ] && hint="[y/N]"
  [ "${YES:-0}" = 1 ] && return 0
  if [ -r /dev/tty ]; then read -r -p "  $q $hint : " a </dev/tty || a=""; fi
  a="${a:-$d}"
  case "$a" in y|Y|yes|YES|ใช่|ครับ|ค่ะ|คะ|ได้) return 0 ;; *) return 1 ;; esac
}

# ---------- หาและแตกไฟล์ zip ----------
# find_src <ชื่อโฟลเดอร์> <ตัวแปร zip> <pattern> <ไฟล์ยืนยัน> <ชื่อ zip บน GitHub>  → พิมพ์ path ซอร์ส
find_src() {
  local name="$1" zipvar="$2" pattern="$3" marker="$4" remote="${5:-}" zip="" d
  zip="${!zipvar:-}"
  for d in "$HERE/$name" "$PWD/$name" "/root/$name" "/opt/$name-src"; do
    [ -f "$d/$marker" ] && { echo "$d"; return 0; }
  done
  if [ -z "$zip" ]; then
    # หา zip หลายที่ (รันผ่าน curl | bash จะไม่มีโฟลเดอร์สคริปต์ จึงไล่หาใน /root /tmp /home ด้วย)
    zip="$(ls -1t "$HERE"/$pattern "$PWD"/$pattern /root/$pattern /tmp/$pattern /home/*/$pattern /opt/$pattern 2>/dev/null | head -n1 || true)"
  fi
  if [ -z "$zip" ] || [ ! -f "$zip" ]; then
    # ตั้ง URL เองได้ เช่น XXTL_URL=https://.../xxtlonline_panel.zip (ไม่ตั้ง = ไม่โหลดจากที่ไหน)
    local urlvar="${zipvar%_ZIP}_URL" url=""; url="${!urlvar:-}"
    if [ -n "$url" ]; then
      command -v curl >/dev/null || { apt-get update -qq; apt-get install -y -qq curl ca-certificates >/dev/null; }
      zip="$WORK/$name.zip"; echo "ดาวน์โหลด $url" >&2
      curl -fsSL "$url" -o "$zip" || { echo "โหลด $url ไม่สำเร็จ" >&2; return 1; }
    fi
  fi
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
  if [ -f "$out/$name/$marker" ]; then echo "$out/$name"
  elif [ -f "$out/$marker" ]; then echo "$out"
  else return 1; fi
}


# ---------- 0) เลือกว่าจะติดตั้งอะไร ----------
MODE="${MODE:-}"
if [ -z "$MODE" ] && [ -r /dev/tty ]; then
  echo
  echo "  จะติดตั้งอะไร?"
  echo "    1) ทั้งสองอย่าง — ติดตั้งแดชบอร์ด VPN (panel) ก่อน แล้วถามอีกครั้งก่อนติดตั้งร้านค้าต่อ"
  echo "    2) เฉพาะแดชบอร์ด VPN (panel)"
  echo "    3) เฉพาะร้านค้า (wselx)"
  read -r -p "  เลือก 1 / 2 / 3 [1]: " MODE </dev/tty || true
fi
case "${MODE:-1}" in
  1|both|all|"") INSTALL_PANEL=1; INSTALL_SHOP=1 ;;
  2|panel)       INSTALL_PANEL=1; INSTALL_SHOP=0 ;;
  3|shop)        INSTALL_PANEL=0; INSTALL_SHOP=1 ;;
  *) die "MODE ไม่ถูกต้อง: '$MODE' (ใช้ 1, 2 หรือ 3)" ;;
esac
XXT_KEY=""; XUI_OK=0; XUI_PASS_ENV=""; CERT_OK=0; DASH_PORT_OK=0; FAIL=0; SHOP_DECLINED=0
# ---------- 1) ถามโดเมน (ข้อเดียว) ----------
DOMAIN="${DOMAIN:-}"
[ -n "$DOMAIN" ] || DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  [ -r /dev/tty ] || die "ระบุโดเมน เช่น: sudo bash setup.sh shop.example.com"
  echo
  echo "  โดเมนนี้ใช้ทั้งร้านค้า (https://โดเมน) แดชบอร์ด (https://โดเมน/panel/) และเป็น Address ในแอป VPN"
  echo "  ต้องตั้ง A record ชี้มาที่ IP เครื่องนี้ก่อน (ถ้าใช้ Cloudflare ให้ปิดเมฆส้ม = DNS only)"
  read -r -p "  โดเมนของคุณ เช่น shop.example.com : " DOMAIN </dev/tty || true
fi
DOMAIN="$(echo "$DOMAIN" | tr 'A-Z' 'a-z' | sed 's|^https\?://||; s|/.*$||; s|[[:space:]]||g')"
[[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$ ]] || die "รูปแบบโดเมนไม่ถูกต้อง: '$DOMAIN'"
EMAIL="${EMAIL:-}"

command -v curl >/dev/null || { apt-get update -qq; apt-get install -y -qq curl ca-certificates >/dev/null; }
IP="$(curl -s4 --max-time 6 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
if [ "${SKIP_DNS_CHECK:-0}" != 1 ]; then
  DNS="$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}' || true)"
  [ "$DNS" = "$IP" ] || die "DNS ของ $DOMAIN ชี้ไปที่ '${DNS:-ไม่พบ}' แต่เครื่องนี้คือ $IP — ตั้ง A record ให้ถูก (Cloudflare ให้ปิดเมฆส้ม) แล้วรันใหม่"
fi

# ---------- 2) บัญชีแอดมินชุดเดียว ----------
OLD_USER=""; OLD_PW=""
if [ -f "$INFO_FILE" ]; then
  OLD_USER="$(awk -F': *' '/ชื่อผู้ใช้/{print $2; exit}' "$INFO_FILE" 2>/dev/null || true)"
  OLD_PW="$(awk -F': *' '/รหัสผ่าน/{print $2; exit}' "$INFO_FILE" 2>/dev/null || true)"
  case "$OLD_PW" in "("*|"") OLD_PW="" ;; esac
  [[ "$OLD_USER" =~ ^[A-Za-z0-9_.-]{3,30}$ ]] || OLD_USER=""
fi
ADMIN_USERNAME="${ADMIN_USERNAME:-${2:-}}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-${3:-}}"
[ -n "$ADMIN_USERNAME" ] || ADMIN_USERNAME="$OLD_USER"
if [ -z "$ADMIN_USERNAME" ] && [ -r /dev/tty ]; then
  read -r -p "  ชื่อผู้ใช้แอดมิน (ใช้ร่วมทุกระบบ) [admin]: " ADMIN_USERNAME </dev/tty || true
fi
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
[[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9_.-]{3,30}$ ]] || die "ADMIN_USERNAME ไม่ถูกต้อง (3-30 ตัว a-z 0-9 _ . -)"
FRESH_SHOP=0; if [ "$INSTALL_SHOP" = 1 ] && [ ! -f "$APP_DIR/.env" ]; then FRESH_SHOP=1; fi
FRESH_DASH=0; if [ "$INSTALL_PANEL" = 1 ] && [ ! -f /etc/xxtlonline/dashboard.json ]; then FRESH_DASH=1; fi
FRESH_XUI=0;  if [ "$INSTALL_PANEL" = 1 ] && [ "${SKIP_3XUI:-0}" != 1 ] && [ ! -x /usr/local/x-ui/x-ui ]; then FRESH_XUI=1; fi
PW_NOTE="(ใช้รหัสเดิมของการติดตั้งก่อนหน้า)"
if [ "$FRESH_SHOP" = 1 ] || [ "$FRESH_DASH" = 1 ] || [ "$FRESH_XUI" = 1 ]; then
  if [ -z "$ADMIN_PASSWORD" ] && [ -n "$OLD_PW" ]; then
    ADMIN_PASSWORD="$OLD_PW"; echo "   ใช้รหัสแอดมินชุดเดิมจากการติดตั้งก่อนหน้า (ทุกระบบใช้รหัสเดียวกัน)"
  fi
  if [ -z "$ADMIN_PASSWORD" ] && [ -r /dev/tty ]; then
    while :; do
      read -rs -p "  รหัสผ่านแอดมิน อย่างน้อย 8 ตัว (กด Enter = สุ่มให้): " P1 </dev/tty || true; echo
      [ -z "$P1" ] && break
      if [ "${#P1}" -lt 8 ]; then warn "สั้นกว่า 8 ตัว ลองใหม่"; continue; fi
      if [[ "$P1" =~ [^A-Za-z0-9\!@%^*_+=.,-] ]]; then warn "ใช้ได้เฉพาะ a-z A-Z 0-9 และ !@%^*_+=.,- (ไม่ใช้เว้นวรรค ' \" \\ \$ \`)"; continue; fi
      read -rs -p "  ยืนยันรหัสผ่านอีกครั้ง: " P2 </dev/tty || true; echo
      [ "$P1" = "$P2" ] && { ADMIN_PASSWORD="$P1"; break; } || warn "สองครั้งไม่ตรงกัน ลองใหม่"
    done
  fi
  [[ -z "$ADMIN_PASSWORD" || "$ADMIN_PASSWORD" =~ ^[A-Za-z0-9\!@%^*_+=.,-]+$ ]] || die "ADMIN_PASSWORD มีอักขระที่ไม่รองรับ (ใช้ a-z A-Z 0-9 !@%^*_+=.,-)"
  ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(openssl rand -hex 10)}"
  [ "${#ADMIN_PASSWORD}" -ge 8 ] || die "ADMIN_PASSWORD ต้องยาวอย่างน้อย 8 ตัว"
  PW_NOTE="$ADMIN_PASSWORD"
  if { [ "$INSTALL_SHOP" = 1 ] && [ "$FRESH_SHOP" = 0 ]; } || { [ "$INSTALL_PANEL" = 1 ] && [ "$FRESH_DASH" = 0 ]; }; then
    warn "บางระบบติดตั้งไว้แล้ว — รหัสใหม่นี้ใช้กับระบบที่ติดตั้งใหม่รอบนี้เท่านั้น (ระบบเดิมใช้รหัสเดิม)"
  fi
else
  ADMIN_PASSWORD=""   # ติดตั้งซ้ำ = อัปเดต ไม่แตะรหัสเดิม
fi

# ---------- 2.5) กันพอร์ต 22 (SSH ของเครื่อง) ไม่ให้ถูกบล็อก ----------
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then ufw allow 22/tcp >/dev/null 2>&1 || true; fi

if [ -z "$ADMIN_PASSWORD" ] && [ -n "$OLD_PW" ]; then PW_NOTE="$OLD_PW"; fi
say "เริ่มติดตั้งสำหรับ $DOMAIN (IP $IP)"

# ---------- 3) ซอร์สโค้ด (หาไฟล์ที่ต้องใช้ก่อน จะได้ไม่ติดตั้งครึ่งทางแล้วค่อยพบว่าไม่มีไฟล์) ----------
XXTL_DIR=""; WSELX_DIR=""
if [ "$INSTALL_PANEL" = 1 ]; then
  XXTL_DIR="$(find_src xxtlonline XXTL_ZIP 'xxtlonline*.zip' install.sh "")" \
    || die "ไม่พบ xxtlonline_panel.zip บนเครื่อง — อัปโหลดไฟล์ไว้ที่ /root/ ก่อน (เช่นจากเครื่องคุณ: scp xxtlonline_panel.zip wselx-sell.zip root@$IP:/root/) แล้วรันใหม่ หรือตั้ง XXTL_ZIP=/path/file.zip หรือ XXTL_URL=https://ลิงก์ไฟล์.zip"
  echo "xxtlonline: $XXTL_DIR (ใช้ตามต้นฉบับ ไม่แก้ไข)"
fi
if [ "$INSTALL_SHOP" = 1 ]; then
  WSELX_DIR="$(find_src wselx WSELX_ZIP 'wselx*.zip' server.js "$WSELX_REMOTE_ZIP")" \
    || die "หา/โหลด wselx ไม่สำเร็จ — อัปโหลด wselx-sell.zip ไว้ที่ /root/ หรือตั้ง WSELX_ZIP=/path/file.zip หรือ WSELX_URL=https://ลิงก์ไฟล์.zip"
  echo "wselx     : $WSELX_DIR"
fi

install_panel() {
if [ "$INSTALL_SHOP" = 1 ] || [ -f "$APP_DIR/.env" ]; then ROOT_DIRECTIVE='proxy_pass http://127.0.0.1:3000;'; else ROOT_DIRECTIVE='return 302 /panel/;'; fi

# ---------- 4) xxtlonline (ติดตั้งด้วย install.sh ตามต้นฉบับ ไม่แก้อะไร) ----------
say "ติดตั้ง xxtlonline"
XXTLONLINE_DASH_USER="$ADMIN_USERNAME" XXTLONLINE_DASH_PASSWORD="$ADMIN_PASSWORD" \
  bash "$XXTL_DIR/install.sh" --yes \
  || die "ติดตั้ง xxtlonline ไม่สำเร็จ (ดูข้อความด้านบน) — แก้แล้วรัน setup.sh ซ้ำได้"
echo; echo "xxtlonline ติดตั้งเสร็จ — ต่อด้วยตั้งค่าเว็บ/HTTPS/ร้านค้า (ยังไม่จบ อย่าเพิ่งปิดหน้าจอ)"
systemctl is-active --quiet xxtlonline-dash || die "แดชบอร์ด xxtlonline ไม่ทำงาน (ดู: journalctl -u xxtlonline-dash -n 30)"
systemctl is-active --quiet xxtlonline-ws   || die "xxtlonline-ws ไม่ทำงาน (ดู: journalctl -u xxtlonline-ws -n 30)"

# ให้แดชบอร์ดรู้จักโดเมนและทำงานใต้ /panel (ไฟล์ตั้งค่านอก zip — วิธีเดียวกับ xxtlonline-https)
printf 'XXTLONLINE_DASH_DOMAIN=%s\nXXTLONLINE_DASH_BASE=/panel\n' "$DOMAIN" > /etc/xxtlonline/dashboard.env
chmod 600 /etc/xxtlonline/dashboard.env
systemctl restart xxtlonline-dash

# ---------- 5) nginx (พอร์ต 443 เท่านั้น — พอร์ต 80 เป็นของ xxtlonline-ws) ----------
say "เตรียม nginx + certbot"
apt-get update -qq
# กัน nginx ที่เพิ่งติดตั้งเปิดขึ้นมาแย่งพอร์ต 80 จาก VPN
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d
apt-get install -y -qq nginx certbot git openssl unzip ca-certificates >/dev/null
rm -f /usr/sbin/policy-rc.d
systemctl stop nginx 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/wselx /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/xxtlonline-dash.conf
mkdir -p /etc/xxtlonline/ssl /etc/letsencrypt/renewal-hooks/deploy
rm -f /etc/letsencrypt/renewal-hooks/deploy/xxtlonline-ws.sh   # hook ของสคริปต์เวอร์ชันเก่า (สั่ง HUP ตัด VPN) ไม่ใช้แล้ว

# ---------- 6) 3x-ui (โหลด release ตรง ไม่ผ่านสคริปต์ติดตั้งแบบถามตอบ) ----------
XUI_OK=0; XUI_PASS_ENV=""
if [ "${SKIP_3XUI:-0}" = 1 ]; then
  echo "ข้าม 3x-ui (SKIP_3XUI=1)"
elif [ -x /usr/local/x-ui/x-ui ]; then
  echo "พบ 3x-ui เดิม — ไม่แตะค่าเดิม"; XUI_OK=1
else
  say "ติดตั้ง 3x-ui"
  case "$(uname -m)" in x86_64|amd64) XA=amd64 ;; aarch64|arm64) XA=arm64 ;; *) XA="" ;; esac
  if [ -z "$XA" ]; then warn "สถาปัตยกรรม $(uname -m) ไม่รองรับในสคริปต์ — ข้าม 3x-ui"
  elif curl -fsSL --retry 3 --max-time 180 -o "$WORK/xui.tgz" "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-$XA.tar.gz" \
       && tar -xzf "$WORK/xui.tgz" -C /usr/local && [ -f /usr/local/x-ui/x-ui ]; then
    cd /usr/local/x-ui
    chmod +x x-ui x-ui.sh bin/xray-linux-* 2>/dev/null || true
    cp -f x-ui.sh /usr/bin/x-ui; chmod +x /usr/bin/x-ui
    cp -f x-ui.service.debian /etc/systemd/system/x-ui.service 2>/dev/null || cp -f x-ui.service /etc/systemd/system/x-ui.service
    cd /
    /usr/local/x-ui/x-ui setting -username "$ADMIN_USERNAME" -password "$ADMIN_PASSWORD" -port "$XUI_PORT" -webBasePath "$XUI_BASE" >/dev/null 2>&1 \
      || warn "ตั้งค่า 3x-ui อัตโนมัติไม่สำเร็จ — ตั้งเองด้วยคำสั่ง x-ui"
    /usr/local/x-ui/x-ui setting -listenIP 127.0.0.1 >/dev/null 2>&1 \
      || warn "3x-ui รุ่นนี้ไม่รองรับ -listenIP — แผงอาจเปิดที่พอร์ต $XUI_PORT ตรง ๆ (ufw บล็อกไว้ให้ ถ้าเปิดใช้งาน)"
    /usr/local/x-ui/x-ui migrate >/dev/null 2>&1 || true
    systemctl daemon-reload; systemctl enable x-ui >/dev/null 2>&1; systemctl restart x-ui
    sleep 2
    if systemctl is-active --quiet x-ui; then XUI_OK=1; XUI_PASS_ENV="$ADMIN_PASSWORD"; else journalctl -u x-ui -n 15 --no-pager || true; warn "3x-ui ไม่ขึ้น — ดู log ด้านบน"; fi
  else
    warn "โหลด 3x-ui ไม่สำเร็จ (ต้องเข้า github.com ได้) — ข้ามไปก่อน รันสคริปต์ซ้ำเมื่อพร้อม"
  fi
fi

# ---------- 7) ใบรับรอง HTTPS (standalone: หยุด xxtlonline-ws ชั่วคราวตอนขอ/ต่ออายุ เพราะพอร์ต 80 เป็นของ VPN) ----------
say "ขอใบรับรอง HTTPS (หยุด VPN ชั่วคราวไม่กี่วินาที)"
CB_MAIL=(--register-unsafely-without-email); [ -n "$EMAIL" ] && CB_MAIL=(-m "$EMAIL")
CB_EXTRA=()
LE_DIR="/etc/letsencrypt/live/$DOMAIN"
RENEW_CONF="/etc/letsencrypt/renewal/$DOMAIN.conf"
CERT_OK=0
if [ -f "$RENEW_CONF" ] && [ -s "$LE_DIR/fullchain.pem" ] && grep -q 'pre_hook = systemctl stop xxtlonline-ws' "$RENEW_CONF"; then
  CERT_OK=1
else
  # เคยออกด้วยวิธีอื่น → ออกใหม่ให้ต่ออายุอัตโนมัติโดยหยุด/เปิด VPN เอง
  [ -f "$RENEW_CONF" ] && CB_EXTRA=(--cert-name "$DOMAIN" --force-renewal)
  if certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos "${CB_MAIL[@]}" "${CB_EXTRA[@]}" \
       --pre-hook "systemctl stop xxtlonline-ws" \
       --post-hook "systemctl start xxtlonline-ws" \
       --deploy-hook "systemctl try-reload-or-restart nginx"; then
    CERT_OK=1
  fi
  systemctl start xxtlonline-ws 2>/dev/null || true
fi
if [ "$CERT_OK" = 1 ]; then
  SSL_CRT="$LE_DIR/fullchain.pem"; SSL_KEY="$LE_DIR/privkey.pem"
else
  warn "ขอใบรับรอง HTTPS ไม่สำเร็จ — ใช้ self-signed ชั่วคราว (เบราว์เซอร์จะเตือน)"
  warn "ตรวจ DNS/พอร์ต 80 เปิดจากภายนอก แล้วรันสคริปต์นี้ซ้ำ (ไม่กระทบข้อมูลเดิม)"
  [ -s /etc/xxtlonline/ssl/cert.pem ] || openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout /etc/xxtlonline/ssl/key.pem -out /etc/xxtlonline/ssl/cert.pem -subj "/CN=$DOMAIN" >/dev/null 2>&1
  chmod 600 /etc/xxtlonline/ssl/key.pem
  SSL_CRT=/etc/xxtlonline/ssl/cert.pem; SSL_KEY=/etc/xxtlonline/ssl/key.pem
fi

# ---------- 8) ตั้งค่า nginx ----------
cat > /etc/nginx/conf.d/wselx-xxtl.conf <<NGX
# สร้างโดย setup.sh — ฟังพอร์ต 443 เท่านั้น (พอร์ต 80 เป็นของ xxtlonline-ws)
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOMAIN};
    ssl_certificate     ${SSL_CRT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    client_max_body_size 15m;

    # แดชบอร์ด xxtlonline อยู่ที่ /panel/
    location = /panel { return 301 /panel/; }
    location /panel/ {
        client_max_body_size 8k;
        proxy_pass http://127.0.0.1:8088/;
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 30s;
        add_header Strict-Transport-Security "max-age=31536000" always;
    }

    # แผง 3x-ui (webBasePath = /${XUI_BASE}/)
    location = /${XUI_BASE} { return 301 /${XUI_BASE}/; }
    location /${XUI_BASE}/ {
        client_max_body_size 8m;
        proxy_pass http://127.0.0.1:${XUI_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 60s;
    }

    # หน้าแรก: ร้านค้า wselx (ถ้ายังไม่ได้ติดตั้งร้านค้า จะเด้งไปแดชบอร์ด)
    location / {
        ${ROOT_DIRECTIVE}
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
NGX

# แดชบอร์ดที่ https://โดเมน:$DASH_HTTPS_PORT (ใช้เมื่อได้ใบรับรองจริงเท่านั้น)
DASH_PORT_OK=0
rm -f /etc/nginx/conf.d/xxtl-dash-port.conf
if [ "$CERT_OK" = 1 ]; then
  cat > /etc/nginx/conf.d/xxtl-dash-port.conf <<NGX
server {
    listen ${DASH_HTTPS_PORT} ssl;
    listen [::]:${DASH_HTTPS_PORT} ssl;
    server_name ${DOMAIN};
    ssl_certificate     ${SSL_CRT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    add_header Strict-Transport-Security "max-age=31536000" always;
    client_max_body_size 8k;
    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_cookie_path /panel /;
        proxy_read_timeout 30s;
    }
}
NGX
  DASH_PORT_OK=1
fi
nginx -t || die "ค่า nginx ไม่ถูกต้อง (ดูข้อความด้านบน)"
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx || die "nginx ไม่ขึ้น (ตรวจพอร์ต 443/${DASH_HTTPS_PORT} ว่าไม่ถูกใช้: ss -ltnp)"

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null || true; ufw allow 443/tcp >/dev/null || true
  [ "$DASH_PORT_OK" != 1 ] || ufw allow "$DASH_HTTPS_PORT"/tcp >/dev/null || true
fi
}

install_shop() {
  PANEL_THERE=0; [ -f /etc/xxtlonline/dashboard.json ] && PANEL_THERE=1
  XXT_KEY=""
  if [ "$PANEL_THERE" = 1 ]; then
if [ -f "$APP_DIR/.env" ] && grep -q '^XXT_LINK_KEY=.\+' "$APP_DIR/.env"; then
  XXT_KEY="$(grep '^XXT_LINK_KEY=' "$APP_DIR/.env" | cut -d= -f2-)"
else
  XXT_KEY="$(python3 /opt/xxtlonline-dash/app.py --create-key "wselx-shop" 127.0.0.1 2>/dev/null | tail -n1 || true)"
  [[ "$XXT_KEY" == xxtl_* ]] || { XXT_KEY=""; warn "สร้าง API Key อัตโนมัติไม่สำเร็จ — สร้างเองที่แดชบอร์ด → เมนู API"; }
fi

  fi
  if [ "$XUI_OK" = 0 ] && [ -x /usr/local/x-ui/x-ui ]; then XUI_OK=1; fi
# ---------- 7) wselx (ร้านค้า) ----------
say "ติดตั้ง wselx"
command -v git >/dev/null || { apt-get update -qq; apt-get install -y -qq git >/dev/null; }
mkdir -p "$WSELX_SRC"
[ -d "$WSELX_SRC/.git" ] || git -C "$WSELX_SRC" init -q -b main
find "$WSELX_SRC" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -a "$WSELX_DIR"/. "$WSELX_SRC"/
# กันบั๊ก BIGINT → string (ปุ่มสั่งซื้อกดไม่ได้) ถ้า zip รุ่นเก่ายังไม่มีแพตช์
if ! grep -q "setTypeParser" "$WSELX_SRC/server.js"; then
  sed -i "0,/^const { Pool } = require('pg');/s//const { Pool, types: pgTypes } = require('pg');\npgTypes.setTypeParser(20, v => parseInt(v, 10));/" "$WSELX_SRC/server.js"
fi
git -C "$WSELX_SRC" add -A
git -C "$WSELX_SRC" -c user.name=setup -c user.email=setup@localhost commit -qm "wselx $(date +%F-%H%M)" 2>/dev/null || true

NONINTERACTIVE=1 SKIP_NGINX="$PANEL_THERE" DOMAIN="$DOMAIN" EMAIL="$EMAIL" \
ADMIN_USERNAME="$ADMIN_USERNAME" ADMIN_PASSWORD="$([ "$FRESH_SHOP" = 1 ] && echo "$ADMIN_PASSWORD" || true)" \
XXT_LINK_KEY="$XXT_KEY" XXT_PANEL_URL="$([ "$PANEL_THERE" = 1 ] && echo "http://127.0.0.1:8088")" \
XUI_PANEL_URL="$([ "$XUI_OK" = 1 ] && echo "http://127.0.0.1:$XUI_PORT/$XUI_BASE")" XUI_USER="$([ -n "$XUI_PASS_ENV" ] && echo "$ADMIN_USERNAME")" XUI_PASS="$XUI_PASS_ENV" \
REPO_URL="$WSELX_SRC" BRANCH=main APP_DIR="$APP_DIR" \
  bash "$WSELX_SRC/install.sh"

  # ติดตั้งร้านค้าทีหลังแดชบอร์ด: เปลี่ยนหน้าแรกจากเด้งไป /panel/ เป็นเปิดร้านค้า
  if [ -f /etc/nginx/conf.d/wselx-xxtl.conf ] && grep -q 'return 302 /panel/;' /etc/nginx/conf.d/wselx-xxtl.conf; then
    sed -i 's#return 302 /panel/;#proxy_pass http://127.0.0.1:3000;#' /etc/nginx/conf.d/wselx-xxtl.conf
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi

  # ร้านค้าที่ https://โดเมน:$SHOP_HTTPS_PORT (ใช้เมื่อมีใบรับรองจริง; ไม่แตะ 3x-ui/แดชบอร์ด)
  rm -f /etc/nginx/conf.d/xxtl-shop-port.conf
  if [ -s "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    cat > /etc/nginx/conf.d/xxtl-shop-port.conf <<NGX
server {
    listen ${SHOP_HTTPS_PORT} ssl;
    listen [::]:${SHOP_HTTPS_PORT} ssl;
    server_name ${DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    client_max_body_size 15m;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
NGX
    if nginx -t >/dev/null 2>&1; then
      systemctl reload nginx || true
      if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow "$SHOP_HTTPS_PORT"/tcp >/dev/null || true; fi
    else
      rm -f /etc/nginx/conf.d/xxtl-shop-port.conf; warn "เปิดร้านค้าที่พอร์ต $SHOP_HTTPS_PORT ไม่สำเร็จ (nginx -t ไม่ผ่าน) — ยังใช้ https://$DOMAIN/ ได้"
    fi
  fi

}

detect_state() {
  HAVE_PANEL=0; [ -f /etc/xxtlonline/dashboard.json ] && HAVE_PANEL=1
  HAVE_SHOP=0;  [ -f "$APP_DIR/.env" ] && HAVE_SHOP=1
  if [ -x /usr/local/x-ui/x-ui ] && systemctl is-active --quiet x-ui 2>/dev/null; then XUI_OK=1; fi
  [ -f /etc/nginx/conf.d/xxtl-dash-port.conf ] && DASH_PORT_OK=1
  if [ "$CERT_OK" != 1 ] && [ -s "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then CERT_OK=1; fi
  return 0
}

write_info() {
  detect_state
  ( umask 077; {
    [ "$HAVE_SHOP" = 1 ]  && echo "ร้านค้า        : https://$DOMAIN/$([ -f /etc/nginx/conf.d/xxtl-shop-port.conf ] && echo "  หรือ https://$DOMAIN:$SHOP_HTTPS_PORT")"
    if [ "$HAVE_PANEL" = 1 ]; then
      echo "แดชบอร์ด VPN  : $([ "$DASH_PORT_OK" = 1 ] && echo "https://$DOMAIN:$DASH_HTTPS_PORT  หรือ ")https://$DOMAIN/panel/"
      [ "$XUI_OK" = 1 ] && echo "3x-ui         : https://$DOMAIN/$XUI_BASE/   (สร้าง inbound แล้วใช้พอร์ตอื่นที่ไม่ใช่ 22/80/443 และเปิดด้วย ufw allow <พอร์ต>/tcp)"
    fi
    echo "แอดมิน (ใช้ร่วมกันทุกระบบ)"
    echo "  ชื่อผู้ใช้   : $ADMIN_USERNAME"
    echo "  รหัสผ่าน    : $PW_NOTE"
    if [ "$HAVE_PANEL" = 1 ]; then
      echo "แอป VPN (NPV / NetMod / HTTP Custom: SSH + HTTP/WebSocket)"
      echo "  Address     : $DOMAIN"
      echo "  SSH + HTTP  : พอร์ต 80"
      echo "  HTTP Proxy  : พอร์ต 80 (ช่อง Proxy = ของค่าย, Address/Port ยังเป็นเครื่องนี้)"
      echo "  (พอร์ต 443 ใช้กับเว็บเท่านั้น ไม่ใช่ VPN)"
      echo "  Response    : 200 Connection established"
      echo "  Payload     : GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]"
    fi
    echo "พอร์ต 22 ว่างไว้ให้ SSH ของเครื่อง (ssh root@$IP) ตามเดิม — สคริปต์นี้ไม่แตะ"
  } > "$INFO_FILE" )
  chmod 600 "$INFO_FILE"
}

# กล่องสรุปลิงก์ + user + รหัส
show_box() {
  detect_state
  echo
  printf '\033[1;32m'
  echo "  ╔══════════════════════════════════════════════════════════"
  [ "$HAVE_SHOP" != 1 ]  || echo "  ║  🛒 หน้าร้านค้า      : https://$DOMAIN/"
  [ "$HAVE_SHOP" != 1 ]  || echo "  ║  🔐 แอดมินร้านค้า    : https://$DOMAIN/   (ล็อกอินด้วยบัญชีแอดมิน)"
  if [ "$HAVE_PANEL" = 1 ]; then
    [ "$DASH_PORT_OK" != 1 ] || echo "  ║  📡 แดชบอร์ด VPN    : https://$DOMAIN:$DASH_HTTPS_PORT"
    echo "  ║  📡 แดชบอร์ด (สำรอง) : https://$DOMAIN/panel/"
    [ "$XUI_OK" != 1 ] || echo "  ║  🧩 แผง 3x-ui        : https://$DOMAIN/$XUI_BASE/"
  fi
  echo "  ║  👤 Username : $ADMIN_USERNAME"
  echo "  ║  🔑 Password : $PW_NOTE"
  echo "  ║  🔌 SSH เครื่อง : ssh root@$IP  (พอร์ต 22 ปกติ)"
  echo "  ╚══════════════════════════════════════════════════════════"
  printf '\033[0m'
  [ "$CERT_OK" = 1 ] || warn "ยังไม่มี HTTPS จริง — เปิดลิงก์ด้านบนแล้วเบราว์เซอร์จะเตือนใบรับรอง (กดดำเนินการต่อได้) แล้วรันสคริปต์ซ้ำเมื่อ DNS พร้อม"
  return 0
}

finish() {
  write_info
  say "ตรวจระบบ"
  sleep 2
  local svcs=() s st
  [ "$HAVE_PANEL" != 1 ] || svcs+=(nginx xxtlonline-dropbear xxtlonline-ws xxtlonline-dash)
  if [ "$HAVE_SHOP" = 1 ]; then svcs+=(wselx); [ "$HAVE_PANEL" = 1 ] || svcs+=(nginx); fi
  [ "$XUI_OK" != 1 ] || svcs+=(x-ui)
  for s in "${svcs[@]}"; do
    st="$(systemctl is-active "$s" || true)"; printf '   %-22s %s\n' "$s" "$st"; [ "$st" = active ] || FAIL=1
  done
  code() { curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$DOMAIN:$2:127.0.0.1" "$1" || echo 000; }
  [ "$HAVE_SHOP" != 1 ]  || echo "   ร้านค้า  https://$DOMAIN/        → HTTP $(code "https://$DOMAIN/" 443)"
  if [ "$HAVE_PANEL" = 1 ]; then
    echo "   แดชบอร์ด https://$DOMAIN/panel/  → HTTP $(code "https://$DOMAIN/panel/" 443)"
    [ "$XUI_OK" != 1 ] || echo "   3x-ui    https://$DOMAIN/$XUI_BASE/   → HTTP $(code "https://$DOMAIN/$XUI_BASE/" 443)"
    local vpn
    vpn="$(python3 - <<'PY' 2>/dev/null || echo ล้มเหลว
import socket
s = socket.create_connection(("127.0.0.1", 80), 5)
s.sendall(b"GET / HTTP/1.1\r\nHost: probe\r\nUpgrade: websocket\r\n\r\n")
r = s.recv(200)
print("ผ่าน" if r.startswith(b"HTTP/1.1 ") else "ล้มเหลว")
PY
)"
    echo "   VPN WebSocket พอร์ต 80          → $vpn"
  fi

  show_box
  if [ "$FAIL" = 0 ]; then say "ติดตั้งเสร็จแล้ว ✅"; else warn "มีบริการที่ไม่ทำงาน ดู: journalctl -u wselx -u xxtlonline-ws -n 40"; fi
  sed 's/^/  /' "$INFO_FILE"
  if [ "$SHOP_DECLINED" = 1 ]; then
    echo; echo "  ยังไม่ได้ติดตั้งร้านค้า — ติดตั้งทีหลังได้: sudo bash setup.sh $DOMAIN  แล้วเลือก 3"
  fi
  if [ "$HAVE_SHOP" = 1 ]; then
    cat <<EOT

  ขั้นต่อไป: เข้า https://$DOMAIN/ ล็อกอินแอดมิน → เมนูเซิร์ฟเวอร์ → กดปุ่ม "เชื่อมแดชบอร์ด" / "เชื่อม 3x-ui"
EOT
  fi
  cat <<EOT
  (ข้อมูลข้างต้นเก็บไว้ที่ $INFO_FILE — ลบทิ้งหลังจดแล้ว)
  อัปเดตเวอร์ชัน: ใส่ zip ใหม่แล้วรัน  sudo bash setup.sh $DOMAIN  ซ้ำ (ไม่แตะรหัส/ฐานข้อมูลเดิม)
EOT
  [ "$FAIL" = 0 ] || exit 1
}

# ---------- ลำดับการติดตั้ง: ทีละอัน แล้วถามก่อนอันถัดไป ----------
if [ "$INSTALL_PANEL" = 1 ]; then
  say "[ติดตั้งอันที่ 1] แดชบอร์ด VPN (panel + 3x-ui)"
  install_panel
  write_info
  say "แดชบอร์ด VPN ติดตั้งเสร็จแล้ว ✅"
  show_box
fi
if [ "$INSTALL_SHOP" = 1 ]; then
  GO_SHOP=1
  if [ "$INSTALL_PANEL" = 1 ]; then
    echo
    ask_yn "ต่อไปคือร้านค้า (wselx) — ติดตั้งต่อเลยไหม?" y || GO_SHOP=0
  fi
  if [ "$GO_SHOP" = 1 ]; then
    say "[ติดตั้ง$([ "$INSTALL_PANEL" = 1 ] && echo "อันที่ 2" || echo "ร้านค้า")] ร้านค้า (wselx)"
    install_shop
  else
    SHOP_DECLINED=1
    # ยังไม่มีร้านค้า → หน้าแรกเด้งไปแดชบอร์ดแทน (กัน 502)
    if [ -f /etc/nginx/conf.d/wselx-xxtl.conf ]; then
      sed -i 's#proxy_pass http://127.0.0.1:3000;#return 302 /panel/;#' /etc/nginx/conf.d/wselx-xxtl.conf
      nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
    fi
  fi
fi
finish
