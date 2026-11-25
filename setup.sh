#!/usr/bin/env bash
# =====================================================================
#  setup.sh — ติดตั้งอัตโนมัติ wselx (ร้านค้า) + xxtlonline (SSH WebSocket + แดชบอร์ด)
#             ถามแค่ "โดเมน" ข้อเดียว (Ubuntu 22.04/24.04, Debian ที่ใช้ apt + systemd)
#
#  วิธีใช้ (วางไฟล์นี้ไว้โฟลเดอร์เดียวกับ wselx-sell.zip และ xxtlonline_panel.zip):
#      sudo bash setup.sh                   # ถามโดเมน แล้วทำให้ทุกอย่าง
#      sudo bash setup.sh shop.example.com  # ไม่ถามอะไรเลย
#  หรือสั่งบรรทัดเดียว (โหลด zip จาก GitHub ให้เอง):
#      curl -fsSL https://raw.githubusercontent.com/ZEROXGCK/xxtlonline/main/setup.sh | sudo bash
#
#  ผลลัพธ์ (โดเมนเดียว ใช้พอร์ต 80 และ 443 ร่วมกันทั้ง VPN และเว็บ):
#      https://โดเมน/         เว็บร้านค้า (wselx)
#      https://โดเมน/panel/   แดชบอร์ด xxtlonline
#      https://โดเมน/xui/     แผง 3x-ui (VLESS/VMess) — ติดตั้งให้ด้วย
#      พอร์ต 80 / 443         แอป VPN (NPV/NetMod/HTTP Custom) ใช้ได้ทั้งสองพอร์ต
#      แอดมิน: ชื่อผู้ใช้/รหัสผ่านชุดเดียวกันทั้งร้านค้า แดชบอร์ด และ 3x-ui
#      ในหน้าแอดมินร้านค้า (เมนูเซิร์ฟเวอร์) มีปุ่ม "เชื่อมแดชบอร์ด" และ "เชื่อม 3x-ui" อัตโนมัติ
#
#  ตัวแปรที่ตั้งเองได้ (ไม่ตั้งก็ได้):
#      DOMAIN          โดเมน (แทนการพิมพ์ตอนถาม)
#      ADMIN_USERNAME  ชื่อแอดมิน (ค่าเริ่มต้น admin)
#      ADMIN_PASSWORD  รหัสแอดมิน (ไม่ตั้ง = สุ่มให้ แสดงตอนจบ + เก็บใน /root/xxtl-wselx-info.txt)
#      EMAIL           อีเมลแจ้งเตือนใบรับรอง (ไม่ตั้ง = ไม่ใช้)
#      WSELX_ZIP / XXTL_ZIP   path ของ zip (ไม่ตั้ง = หาข้างสคริปต์ หรือโหลดจาก GitHub)
#      SKIP_DNS_CHECK=1       ข้ามการตรวจ DNS (ไม่แนะนำ)
#      SKIP_3XUI=1            ไม่ติดตั้ง 3x-ui
# =====================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
WSELX_SRC="${WSELX_SRC:-/opt/wselx-src}"
APP_DIR="${APP_DIR:-/opt/wselx}"
GH_REPO="${GH_REPO:-ZEROXGCK/xxtlonline}"
GH_BRANCH="${GH_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/$GH_REPO/$GH_BRANCH"
WSELX_REMOTE_ZIP="${WSELX_REMOTE_ZIP:-wselx-sell.zip}"
XXTL_REMOTE_ZIP="${XXTL_REMOTE_ZIP:-xxtlonline_panel.zip}"
WEB_HTTP_PORT=8081      # nginx ฝั่งหลังบ้าน (ฟัง 127.0.0.1 เท่านั้น) — รับต่อจากพอร์ต 80
WEB_TLS_PORT=8082       # nginx ฝั่งหลังบ้าน (ฟัง 127.0.0.1 เท่านั้น) — รับต่อจากพอร์ต 443
XUI_PORT=2053           # พอร์ตแผง 3x-ui (ฟัง 127.0.0.1 เท่านั้น เข้าผ่าน https://โดเมน/xui/)
XUI_BASE=xui
XXTL_CONF=/etc/xxtlonline/xxtlonline.conf
INFO_FILE=/root/xxtl-wselx-info.txt
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

case "${1:-}" in -h|--help) sed -n '2,31p' "$0" 2>/dev/null || true; exit 0 ;; esac
[ "$(id -u)" -eq 0 ] || die "ต้องรันด้วย root — ใช้: sudo bash setup.sh"
command -v apt-get >/dev/null && command -v systemctl >/dev/null || die "รองรับเฉพาะ Ubuntu/Debian (apt + systemd)"
export DEBIAN_FRONTEND=noninteractive

# ---------- หาและแตกไฟล์ zip ----------
# find_src <ชื่อโฟลเดอร์> <ตัวแปร zip> <pattern> <ไฟล์ยืนยัน> <ชื่อ zip บน GitHub>  → พิมพ์ path ซอร์ส
find_src() {
  local name="$1" zipvar="$2" pattern="$3" marker="$4" remote="${5:-}" zip="" d
  zip="${!zipvar:-}"
  for d in "$HERE/$name" "$PWD/$name"; do
    [ -f "$d/$marker" ] && { echo "$d"; return 0; }
  done
  if [ -z "$zip" ]; then
    zip="$(ls -1t "$HERE"/$pattern "$PWD"/$pattern 2>/dev/null | head -n1 || true)"
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
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
[[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9_.-]{3,30}$ ]] || die "ADMIN_USERNAME ไม่ถูกต้อง (3-30 ตัว a-z 0-9 _ . -)"
FRESH_SHOP=0; [ -f "$APP_DIR/.env" ] || FRESH_SHOP=1
FRESH_DASH=0; [ -f /etc/xxtlonline/dashboard.json ] || FRESH_DASH=1
PW_NOTE="(ใช้รหัสเดิมของการติดตั้งก่อนหน้า)"
FRESH_XUI=0; [ "${SKIP_3XUI:-0}" != 1 ] && [ ! -x /usr/local/x-ui/x-ui ] && FRESH_XUI=1
if [ "$FRESH_SHOP" = 1 ] || [ "$FRESH_DASH" = 1 ] || [ "$FRESH_XUI" = 1 ]; then
  ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(openssl rand -hex 10)}"
  [ "${#ADMIN_PASSWORD}" -ge 8 ] || die "ADMIN_PASSWORD ต้องยาวอย่างน้อย 8 ตัว"
  PW_NOTE="$ADMIN_PASSWORD"
  if [ "$FRESH_SHOP" = 0 ] || [ "$FRESH_DASH" = 0 ]; then
    warn "บางระบบติดตั้งไว้แล้ว — รหัสใหม่นี้ใช้กับระบบที่ติดตั้งใหม่รอบนี้เท่านั้น (ระบบเดิมใช้รหัสเดิม)"
  fi
else
  ADMIN_PASSWORD=""   # ติดตั้งซ้ำ = อัปเดต ไม่แตะรหัสเดิม
fi

say "เริ่มติดตั้งสำหรับ $DOMAIN (IP $IP)"

# ---------- 3) ซอร์สโค้ด ----------
XXTL_DIR="$(find_src xxtlonline XXTL_ZIP 'xxtlonline*.zip' install.sh "$XXTL_REMOTE_ZIP")" \
  || die "หา/โหลด xxtlonline ไม่สำเร็จ — วาง xxtlonline_panel.zip ไว้ข้างสคริปต์ หรือตั้ง XXTL_ZIP=/path/file.zip"
WSELX_DIR="$(find_src wselx WSELX_ZIP 'wselx*.zip' server.js "$WSELX_REMOTE_ZIP")" \
  || die "หา/โหลด wselx ไม่สำเร็จ — วาง wselx-sell.zip ไว้ข้างสคริปต์ หรือตั้ง WSELX_ZIP=/path/file.zip"
echo "xxtlonline: $XXTL_DIR"; echo "wselx     : $WSELX_DIR"
# แก้บั๊กเก่าใน install.sh (บรรทัดหา SSH port ใช้ pipe ร่วมกับ pipefail) — แก้ซ้ำได้ปลอดภัย
sed -i "s#awk '/^port /{print \$2; exit}')#awk '/^port /{print \$2; exit}' || true)#" "$XXTL_DIR/install.sh"

# ---------- 4) nginx ฝั่งหลังบ้าน (ไม่แย่งพอร์ต 80/443 จาก VPN) ----------
say "เตรียม nginx + certbot"
apt-get update -qq
# กัน nginx ที่เพิ่งติดตั้งเปิดขึ้นมาแย่งพอร์ต 80
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d
apt-get install -y -qq nginx certbot git openssl unzip ca-certificates >/dev/null
rm -f /usr/sbin/policy-rc.d
systemctl stop nginx 2>/dev/null || true
# เคลียร์ค่าเก่าที่เคยฟังพอร์ต 80/443 (ติดตั้งแบบเก่า)
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/wselx /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/xxtlonline-dash.conf
mkdir -p /var/www/letsencrypt

cat > /etc/nginx/conf.d/wselx-xxtl.conf <<NGX
# สร้างโดย setup.sh — ฟังเฉพาะ 127.0.0.1 ; พอร์ต 80/443 จริงเป็นของ xxtlonline-ws ซึ่งแยกทราฟฟิกเว็บมาให้ที่นี่ (PROXY protocol)
server {
    listen 127.0.0.1:${WEB_HTTP_PORT} proxy_protocol;
    server_name ${DOMAIN};
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
    location ^~ /.well-known/acme-challenge/ { root /var/www/letsencrypt; default_type text/plain; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 127.0.0.1:${WEB_TLS_PORT} proxy_protocol;
    server_name ${DOMAIN};
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
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

    # ร้านค้า wselx
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
NGX
nginx -t || die "ค่า nginx ไม่ถูกต้อง (ดูข้อความด้านบน)"
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx || die "nginx ไม่ขึ้น (ตรวจพอร์ต ${WEB_HTTP_PORT}/${WEB_TLS_PORT} ว่าไม่ถูกใช้: ss -ltnp)"

# ---------- 5) xxtlonline (SSH WebSocket พอร์ต 80 + TLS พอร์ต 443 + แดชบอร์ด) ----------
say "ติดตั้ง xxtlonline"
XXTLONLINE_DASH_USER="$ADMIN_USERNAME" XXTLONLINE_DASH_PASSWORD="$ADMIN_PASSWORD" \
  bash "$XXTL_DIR/install.sh" --yes --ssl-port 443

systemctl is-active --quiet xxtlonline-dash || die "แดชบอร์ด xxtlonline ไม่ทำงาน (ดู: journalctl -u xxtlonline-dash -n 30)"

say "ตั้งให้ VPN กับเว็บใช้พอร์ต 80/443 ร่วมกัน"
[ -f "$XXTL_CONF" ] || die "ไม่พบ $XXTL_CONF"
sed -i '/^WEB_DOMAIN=/d; /^WEB_HTTP_BACKEND=/d; /^WEB_TLS_BACKEND=/d' "$XXTL_CONF"
{
  echo "WEB_DOMAIN=$DOMAIN"
  echo "WEB_HTTP_BACKEND=127.0.0.1:$WEB_HTTP_PORT"
  echo "WEB_TLS_BACKEND=127.0.0.1:$WEB_TLS_PORT"
} >> "$XXTL_CONF"
printf 'XXTLONLINE_DASH_DOMAIN=%s\nXXTLONLINE_DASH_BASE=/panel\n' "$DOMAIN" > /etc/xxtlonline/dashboard.env
chmod 600 /etc/xxtlonline/dashboard.env
systemctl restart xxtlonline-ws xxtlonline-dash
sleep 1
systemctl is-active --quiet xxtlonline-ws || { journalctl -u xxtlonline-ws -n 20 --no-pager; die "xxtlonline-ws ไม่ขึ้น"; }

# ---------- 6) API Key ให้ปุ่ม "เชื่อมแดชบอร์ด" ในร้านค้า (ใช้ได้จากเครื่องนี้เท่านั้น) ----------
XXT_KEY=""
if [ -f "$APP_DIR/.env" ] && grep -q '^XXT_LINK_KEY=.\+' "$APP_DIR/.env"; then
  XXT_KEY="$(grep '^XXT_LINK_KEY=' "$APP_DIR/.env" | cut -d= -f2-)"
else
  XXT_KEY="$(python3 /opt/xxtlonline-dash/app.py --create-key "wselx-shop" 127.0.0.1 2>/dev/null | tail -n1 || true)"
  [[ "$XXT_KEY" == xxtl_* ]] || { XXT_KEY=""; warn "สร้าง API Key อัตโนมัติไม่สำเร็จ — สร้างเองที่แดชบอร์ด → เมนู API"; }
fi

# ---------- 6.5) 3x-ui (โหลด release ตรง ไม่ผ่านสคริปต์ติดตั้งแบบถามตอบ) ----------
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

NONINTERACTIVE=1 SKIP_NGINX=1 DOMAIN="$DOMAIN" EMAIL="$EMAIL" \
ADMIN_USERNAME="$ADMIN_USERNAME" ADMIN_PASSWORD="$([ "$FRESH_SHOP" = 1 ] && echo "$ADMIN_PASSWORD" || true)" \
XXT_LINK_KEY="$XXT_KEY" XXT_PANEL_URL="http://127.0.0.1:8088" \
XUI_PANEL_URL="$([ "$XUI_OK" = 1 ] && echo "http://127.0.0.1:$XUI_PORT/$XUI_BASE")" XUI_USER="$([ -n "$XUI_PASS_ENV" ] && echo "$ADMIN_USERNAME")" XUI_PASS="$XUI_PASS_ENV" \
REPO_URL="$WSELX_SRC" BRANCH=main APP_DIR="$APP_DIR" \
  bash "$WSELX_SRC/install.sh"

# ---------- 8) ใบรับรอง HTTPS (webroot ผ่านพอร์ต 80 ที่ xxtlonline-ws ส่งต่อให้ nginx — ไม่ต้องหยุด VPN) ----------
say "ขอใบรับรอง HTTPS"
mkdir -p /etc/xxtlonline/ssl /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/xxtlonline-ws.sh <<HOOK
#!/bin/sh
# หลัง certbot ออก/ต่ออายุใบรับรอง: คัดลอกให้ xxtlonline-ws (พอร์ต 443) แล้วสั่งโหลดใหม่โดยไม่ตัด session
L=/etc/letsencrypt/live/${DOMAIN}
[ -n "\$RENEWED_LINEAGE" ] && [ "\$RENEWED_LINEAGE" != "\$L" ] && exit 0
[ -s "\$L/fullchain.pem" ] || exit 0
install -m 600 "\$L/privkey.pem"   /etc/xxtlonline/ssl/key.pem
install -m 644 "\$L/fullchain.pem" /etc/xxtlonline/ssl/cert.pem
systemctl kill -s HUP --kill-who=main xxtlonline-ws 2>/dev/null || true
HOOK
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/xxtlonline-ws.sh

CB_MAIL=(--register-unsafely-without-email); [ -n "$EMAIL" ] && CB_MAIL=(-m "$EMAIL")
CB_EXTRA=()
RENEW_CONF="/etc/letsencrypt/renewal/$DOMAIN.conf"
CERT_OK=0
if [ -f "$RENEW_CONF" ] && grep -q '^authenticator = webroot' "$RENEW_CONF" && [ -s "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  CERT_OK=1
else
  # เคยออกด้วยวิธีเก่า (nginx/standalone) → ออกใหม่ด้วย webroot เพื่อให้ต่ออายุอัตโนมัติได้โดยไม่ต้องหยุด VPN
  [ -f "$RENEW_CONF" ] && CB_EXTRA=(--cert-name "$DOMAIN" --force-renewal)
  if certbot certonly --webroot -w /var/www/letsencrypt -d "$DOMAIN" --non-interactive --agree-tos "${CB_MAIL[@]}" "${CB_EXTRA[@]}"; then
    CERT_OK=1
  fi
fi
if [ "$CERT_OK" = 1 ]; then
  RENEWED_LINEAGE="" /etc/letsencrypt/renewal-hooks/deploy/xxtlonline-ws.sh
else
  warn "ขอใบรับรอง HTTPS ไม่สำเร็จ — ตอนนี้พอร์ต 443 ใช้ใบรับรอง self-signed (เบราว์เซอร์จะเตือน)"
  warn "ตรวจ DNS/พอร์ต 80 เปิดจากภายนอก แล้วรันสคริปต์นี้ซ้ำ (ไม่กระทบข้อมูลเดิม)"
fi

# ---------- 9) firewall + ตรวจระบบ ----------
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null || true; ufw allow 443/tcp >/dev/null || true
fi

say "ตรวจระบบ"
sleep 2
FAIL=0
for s in nginx xxtlonline-dropbear xxtlonline-ws xxtlonline-dash wselx $([ "$XUI_OK" = 1 ] && echo x-ui); do
  st="$(systemctl is-active "$s" || true)"; printf '   %-22s %s\n' "$s" "$st"; [ "$st" = active ] || FAIL=1
done
code() { curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$DOMAIN:$2:127.0.0.1" "$1" || echo 000; }
echo "   ร้านค้า  https://$DOMAIN/        → HTTP $(code "https://$DOMAIN/" 443)"
echo "   แดชบอร์ด https://$DOMAIN/panel/  → HTTP $(code "https://$DOMAIN/panel/" 443)"
[ "$XUI_OK" != 1 ] || echo "   3x-ui    https://$DOMAIN/$XUI_BASE/   → HTTP $(code "https://$DOMAIN/$XUI_BASE/" 443)"
echo "   http://$DOMAIN/ (ควรเด้งไป https) → HTTP $(code "http://$DOMAIN/" 80)"
VPN_OK="$(python3 - <<'PY' 2>/dev/null || echo ล้มเหลว
import socket
for port in (80,):
    s = socket.create_connection(("127.0.0.1", port), 5)
    s.sendall(b"GET / HTTP/1.1\r\nHost: probe\r\nUpgrade: websocket\r\n\r\n")
    r = s.recv(200)
    print("ผ่าน" if r.startswith(b"HTTP/1.1 ") else "ล้มเหลว")
PY
)"
echo "   VPN WebSocket พอร์ต 80          → $VPN_OK"

# ---------- 10) สรุป ----------
umask 077
cat > "$INFO_FILE" <<EOF
ร้านค้า        : https://$DOMAIN/
แดชบอร์ด VPN  : https://$DOMAIN/panel/
$([ "$XUI_OK" = 1 ] && echo "3x-ui         : https://$DOMAIN/$XUI_BASE/   (สร้าง inbound แล้วใช้พอร์ตอื่นที่ไม่ใช่ 22/80/443 และเปิดด้วย ufw allow <พอร์ต>/tcp)")
แอดมิน (ใช้ร่วมกันทั้งสามระบบ)
  ชื่อผู้ใช้   : $ADMIN_USERNAME
  รหัสผ่าน    : $PW_NOTE
แอป VPN (NPV / NetMod / HTTP Custom: SSH + HTTP/WebSocket)
  Address     : $DOMAIN
  SSH + HTTP  : พอร์ต 22 หรือ 80
  HTTP Proxy  : พอร์ต 80 (ช่อง Proxy = ของค่าย, Address/Port ยังเป็นเครื่องนี้)
  SSL/TLS     : พอร์ต 443 (ตั้ง SNI = $DOMAIN)
  Response    : 200 Connection established
  Payload     : GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf][crlf]
  (พอร์ต 80 ใช้ร่วมกับเว็บ: payload ต้องมี Upgrade: websocket เพื่อแยกจากการเปิดเว็บ — พอร์ต 22 เป็น VPN ล้วน)
SSH ของแอดมินเซิร์ฟเวอร์ถูกย้ายไปพอร์ต 2222 (ssh -p 2222 root@$IP) เพราะพอร์ต 22 ใช้เป็น SSH+HTTP
EOF
chmod 600 "$INFO_FILE"

echo
if [ "$FAIL" = 0 ]; then say "ติดตั้งเสร็จแล้ว ✅"; else warn "มีบริการที่ไม่ทำงาน ดู: journalctl -u wselx -u xxtlonline-ws -n 40"; fi
sed 's/^/  /' "$INFO_FILE"
cat <<EOF

  ขั้นต่อไป: เข้า https://$DOMAIN/ ล็อกอินแอดมิน → เมนูเซิร์ฟเวอร์ → กดปุ่ม "เชื่อมแดชบอร์ด" / "เชื่อม 3x-ui"
  (ข้อมูลข้างต้นเก็บไว้ที่ $INFO_FILE — ลบทิ้งหลังจดแล้ว)
  อัปเดตเวอร์ชัน: ใส่ zip ใหม่แล้วรัน  sudo bash setup.sh $DOMAIN  ซ้ำ (ไม่แตะรหัส/ฐานข้อมูลเดิม)
EOF
[ "$FAIL" = 0 ] || exit 1
