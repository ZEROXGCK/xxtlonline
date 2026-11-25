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
#      3) ตั้ง HTTPS แดชบอร์ด xxtlonline ผ่านโดเมน/ซับโดเมน (ใช้ร่วมกับ nginx ของร้านค้า)
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


# ---------- ลงสองตัวบนเครื่องเดียวกัน: จัดการพอร์ต 80 ----------
XXTL_CONF=/etc/xxtlonline/xxtlonline.conf
SHARED_WS_PORT="${SHARED_WS_PORT:-8080}"

confirm() { # confirm "คำถาม"  (ค่าเริ่มต้น = Y, ไม่มีเทอร์มินัล = Y)
  local a=""
  [ -r /dev/tty ] || return 0
  read -r -p "$1 [Y/n]: " a </dev/tty || true
  case "${a:-Y}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# nginx (ร้านค้า) ฟังพอร์ต 80 อยู่หรือไม่
nginx_on_80() { ss -ltnH "sport = :80" 2>/dev/null | grep -q . && ss -ltnpH "sport = :80" 2>/dev/null | grep -q nginx; }

# ถ้า xxtlonline-ws ถือพอร์ต 80 อยู่ → ย้ายไป $SHARED_WS_PORT เพื่อเปิดทางให้ nginx
move_ws_off_80() {
  [ -f "$XXTL_CONF" ] && grep -qx 'WS_PORT=80' "$XXTL_CONF" || return 0
  warn "xxtlonline-ws ใช้พอร์ต 80 — nginx (HTTPS ร้านค้า/แดชบอร์ด) ต้องใช้พอร์ต 80 ด้วย จึงต้องย้าย WebSocket ไปพอร์ต $SHARED_WS_PORT"
  warn "ผลคือแอป VPN (NPV/NetMod) ต้องเปลี่ยนพอร์ตจาก 80 เป็น $SHARED_WS_PORT"
  confirm "ย้ายไปพอร์ต $SHARED_WS_PORT เลยไหม" || { warn "ไม่ย้าย — nginx จะขอใบรับรอง HTTPS ไม่ผ่าน"; return 0; }
  sed -i "s/^WS_PORT=.*/WS_PORT=$SHARED_WS_PORT/" "$XXTL_CONF"
  systemctl restart xxtlonline-ws || warn "รีสตาร์ท xxtlonline-ws ไม่สำเร็จ ดู: journalctl -u xxtlonline-ws -n 30"
  if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow "$SHARED_WS_PORT/tcp" >/dev/null || true; fi
}

# ---------- 3) HTTPS แดชบอร์ด xxtlonline ผ่าน nginx ที่ใช้ร่วมกับร้านค้า ----------
# ใช้โดเมนคนละชื่อกับร้านค้า (เช่นซับโดเมน panel.xxx.com ชี้ A record มา IP เดียวกัน)
dash_https_shared() {
  local domain="${1:-}" email="${2:-}" ip dns
  [ -f /opt/xxtlonline-dash/app.py ] || die "ยังไม่ได้ติดตั้งแดชบอร์ด xxtlonline — ใช้เมนู 2 ก่อน"
  systemctl is-active --quiet xxtlonline-dash || die "บริการ xxtlonline-dash ไม่ทำงาน (ดู: journalctl -u xxtlonline-dash -n 30)"
  if [ -z "$domain" ]; then
    [ -r /dev/tty ] || die "ระบุโดเมน เช่น: sudo bash setup.sh 3 panel.example.com"
    read -r -p "โดเมนแดชบอร์ด เช่น panel.example.com (ต้องคนละชื่อกับโดเมนร้านค้า): " domain </dev/tty || true
  fi
  domain="$(echo "$domain" | tr 'A-Z' 'a-z' | sed 's|^https\?://||; s|/.*$||')"
  [[ "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$ ]] || die "รูปแบบโดเมนไม่ถูกต้อง: $domain"
  if [ -z "$email" ] && [ -r /dev/tty ]; then read -r -p "อีเมลแจ้งเตือนใบรับรองหมดอายุ (เว้นว่างได้): " email </dev/tty || true; fi
  if [ -n "$email" ] && [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then die "รูปแบบอีเมลไม่ถูกต้อง"; fi

  # ถ้าร้านค้าใช้โดเมนนี้อยู่แล้ว nginx จะชนกัน
  if grep -rqs "server_name[[:space:]]\+$domain[[:space:];]" /etc/nginx/sites-enabled /etc/nginx/conf.d --exclude=xxtlonline-dash.conf; then
    die "โดเมน $domain ถูกใช้โดยเว็บอื่นใน nginx แล้ว (เช่นร้านค้า) — ใช้ซับโดเมนอื่น เช่น panel.${domain#*.}"
  fi

  ip="$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  dns="$(getent ahostsv4 "$domain" | awk '{print $1; exit}' || true)"
  if [ "$dns" != "$ip" ]; then
    die "DNS ของ $domain ชี้ไปที่ '${dns:-ไม่พบ}' แต่เครื่องนี้คือ $ip — ตั้ง A record ให้ถูกก่อน (Cloudflare ให้ปิดเมฆส้ม) แล้วรันใหม่"
  fi

  move_ws_off_80

  say "ติดตั้ง nginx + certbot"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq nginx certbot python3-certbot-nginx >/dev/null

  say "ตั้งค่า nginx สำหรับ $domain → แดชบอร์ด 127.0.0.1:8088"
  # เขียนทับบล็อกเก่าของ xxtlonline-https (แบบพอร์ต 443 อย่างเดียว) ด้วยแบบพอร์ต 80 แล้วให้ certbot เติม HTTPS เอง
  cat > /etc/nginx/conf.d/xxtlonline-dash.conf <<NGX
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    client_max_body_size 8k;
    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }
}
NGX
  nginx -t || die "ค่า nginx ไม่ถูกต้อง (ดูข้อความด้านบน)"
  systemctl enable --now nginx >/dev/null 2>&1 || true
  systemctl reload nginx || systemctl restart nginx || die "nginx ไม่ขึ้น — เช็กว่าพอร์ต 80 ว่าง: ss -ltnp | grep ':80 '"

  say "ขอใบรับรอง HTTPS"
  local mail=(--register-unsafely-without-email); [ -n "$email" ] && mail=(-m "$email")
  certbot --nginx -d "$domain" --non-interactive --agree-tos "${mail[@]}" --redirect \
    || die "ขอใบรับรองไม่สำเร็จ — เช็กว่าพอร์ต 80 ตอบจาก nginx: curl -I http://$domain/"

  printf 'XXTLONLINE_DASH_DOMAIN=%s\n' "$domain" > /etc/xxtlonline/dashboard.env
  chmod 600 /etc/xxtlonline/dashboard.env
  systemctl restart xxtlonline-dash || true
  if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow 'Nginx Full' >/dev/null || true; fi

  say "เสร็จแล้ว"
  echo "  แดชบอร์ด xxtlonline : https://$domain"
  echo "  ใส่ URL นี้ในช่อง Dashboard URL ของเซิร์ฟเวอร์ XXTLONLINE ใน wselx"
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

  # แก้บั๊ก: PostgreSQL ส่ง BIGINT (id สินค้า/แพ็กเกจ/ออเดอร์) มาเป็น string แต่หน้าเว็บเทียบด้วย ===
  # กับตัวเลข ทำให้ปุ่ม "สั่งซื้อ" ไม่เกิดอะไรเลย → แปลง BIGINT เป็นตัวเลขตั้งแต่ฝั่งเซิร์ฟเวอร์ (แก้ซ้ำได้ปลอดภัย)
  if ! grep -q "setTypeParser" "$WSELX_SRC/server.js"; then
    sed -i "0,/^const { Pool } = require('pg');/s//const { Pool, types: pgTypes } = require('pg');\npgTypes.setTypeParser(20, v => parseInt(v, 10)); \/\/ BIGINT -> number/" "$WSELX_SRC/server.js"
    grep -q "setTypeParser" "$WSELX_SRC/server.js" || warn "แพตช์ id (BIGINT) ไม่สำเร็จ — ปุ่มสั่งซื้ออาจยังกดไม่ได้"
  fi
  git -C "$WSELX_SRC" add -A
  git -C "$WSELX_SRC" -c user.name=setup -c user.email=setup@localhost \
      commit -qm "wselx $(date +%F-%H%M)" 2>/dev/null || true

  # ถ้าเครื่องนี้มี xxtlonline ถือพอร์ต 80 อยู่ ต้องย้ายก่อน ไม่งั้น nginx ขอ HTTPS ไม่ผ่าน
  move_ws_off_80

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
  # เครื่องนี้มี nginx/ร้านค้าถือพอร์ต 80 → ย้าย WebSocket ไปพอร์ตอื่น และจัดการโดเมนแดชบอร์ดผ่าน nginx ตัวเดียวกัน
  local args=("$@") a_dom="" a_mail="" has_ws=0 no_dash=0 shared=0 clean=() i=0
  while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
      --ws-port) has_ws=1; clean+=("${args[$i]}" "${args[$((i+1))]:-}"); i=$((i+2)) ;;
      --domain)  a_dom="${args[$((i+1))]:-}";  i=$((i+2)) ;;
      --email)   a_mail="${args[$((i+1))]:-}"; i=$((i+2)) ;;
      --no-dashboard) no_dash=1; clean+=("${args[$i]}"); i=$((i+1)) ;;
      *) clean+=("${args[$i]}"); i=$((i+1)) ;;
    esac
  done
  if [ "$has_ws" = 0 ] && { nginx_on_80 || systemctl is-active --quiet wselx 2>/dev/null; }; then
    shared=1
    warn "เครื่องนี้มีร้านค้า/nginx ใช้พอร์ต 80 อยู่ → ตั้ง WebSocket ของ xxtlonline ที่พอร์ต $SHARED_WS_PORT (แอป VPN ใช้พอร์ต $SHARED_WS_PORT)"
    clean+=(--ws-port "$SHARED_WS_PORT")
  fi
  if [ "$shared" = 0 ] && [ "$has_ws" = 0 ]; then
    # ไม่ได้ลงร่วมกัน → ส่งต่อตัวเลือกเดิมให้ install.sh จัดการ (รวม --domain/--email)
    [ -n "$a_dom" ]  && clean+=(--domain "$a_dom")
    [ -n "$a_mail" ] && clean+=(--email "$a_mail")
  elif [ -n "$a_dom$a_mail" ] && [ "$shared" = 0 ]; then
    [ -n "$a_dom" ]  && clean+=(--domain "$a_dom")
    [ -n "$a_mail" ] && clean+=(--email "$a_mail")
  fi

  # ติดตั้งจากไฟล์ในเครื่องโดยตรง (ไม่ดึงจาก GitHub) — ต้องรันจาก path จริงเพื่อให้สคริปต์หา src/ เจอ
  bash "$src/install.sh" "${clean[@]}"

  if [ "$shared" = 1 ] && [ "$no_dash" = 0 ]; then
    say "ตั้ง HTTPS แดชบอร์ด (ใช้ nginx ร่วมกับร้านค้า)"
    echo "ใช้โดเมน/ซับโดเมนที่ไม่ซ้ำกับร้านค้า เช่น panel.example.com (A record ชี้มาเครื่องนี้) — เว้นว่าง = ข้าม ทำทีหลังด้วย: sudo bash setup.sh 3"
    if [ -n "$a_dom" ] || [ -r /dev/tty ]; then
      local d="$a_dom"
      [ -n "$d" ] || read -r -p "โดเมนแดชบอร์ด: " d </dev/tty || true
      if [ -n "$d" ]; then dash_https_shared "$d" "$a_mail" || warn "ตั้ง HTTPS แดชบอร์ดไม่สำเร็จ — แก้แล้วรัน: sudo bash setup.sh 3 $d"; fi
    fi
  fi
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
    3) ตั้ง HTTPS แดชบอร์ด xxtlonline (ใช้ร่วมกับ nginx ร้านค้า)
    0) ออก
  ============================================
MENU
  read -r -p "เลือก [1/2/3/0]: " choice </dev/tty || true
fi

case "$choice" in
  1) install_wselx "$@" ;;
  2) install_xxtl  "$@" ;;
  3) dash_https_shared "$@" ;;
  0|q|"") echo "ออกแล้ว"; exit 0 ;;
  *) die "ไม่รู้จักตัวเลือก: $choice (ใช้ 1, 2, 3 หรือ 0)" ;;
esac
