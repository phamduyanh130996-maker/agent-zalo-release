#!/bin/sh
# install.sh — cai dat Agent Zalo cho khach hang, chay tren VPS Ubuntu
# 24.04 (hoac tuong duong) TRONG, chua tung cai gi lien quan du an.
#
# Cach dung (khach dan dung 1 dong nay, GHCR_TOKEN la ma rieng cap theo
# tung don hang, nguoi ban gui kem):
#   curl -fsSL https://raw.githubusercontent.com/phamduyanh130996-maker/agent-zalo-release/main/install.sh | sudo sh -s -- <GHCR_TOKEN>
#
# Cai dat tu dong khong tuong tac (danh cho test/CI, KHONG can khach hang
# biet toi) - dat truoc cac bien nay de bo qua tung cau hoi:
#   INSTALL_AUTO_YES=y INSTALL_BOT_NAME="Ten Bot" INSTALL_OWNER_UID="" \
#   INSTALL_DASHBOARD_PASSWORD="" sh install.sh <GHCR_TOKEN>
#
# Phase 6 cua ke hoach dong goi
# (plans/260923-1504-dong-goi-docker-ban-khach-hang-khong-anh-huong-bot-dang-test).
set -eu

GHCR_TOKEN="${1:?Thieu ma cai dat. Lien he nguoi ban de lay dung dong lenh cai dat cho don hang cua ban.}"
GHCR_NAMESPACE="${GHCR_NAMESPACE:-ghcr.io/phamduyanh130996-maker}"
IMAGE_TAG="${IMAGE_TAG:-v1.0.0}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/agent-zalo}"
COMPOSE_URL="${COMPOSE_URL:-https://raw.githubusercontent.com/phamduyanh130996-maker/agent-zalo-release/main/docker-compose.release.yml}"
ENV_EXAMPLE_URL="${ENV_EXAMPLE_URL:-https://raw.githubusercontent.com/phamduyanh130996-maker/agent-zalo-release/main/.env.example}"

say()  { printf '\n>>> %s\n' "$1"; }
warn() { printf '\n!!! %s\n' "$1"; }
die()  { warn "$1"; exit 1; }

say "Bat dau cai dat Agent Zalo. Toan bo qua trinh mat khoang 3-5 phut."

# ===== Buoc 1: kiem tra quyen root =====
if [ "$(id -u)" != "0" ]; then
  die "Can chay bang quyen root. Thu lai voi: curl ... | sudo sh -s -- <ma-cai-dat>"
fi

# ===== Buoc 2: kiem tra/cai Docker =====
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  say "Da phat hien Docker + Docker Compose, bo qua buoc cai dat."
else
  say "Chua co Docker. Se cai dat tu dong bang script chinh thuc cua Docker."
  if [ -n "${INSTALL_AUTO_YES:-}" ]; then
    CONFIRM="$INSTALL_AUTO_YES"
  else
    printf 'Ban co dong y cai Docker vao may nay khong? (y/n): '
    read -r CONFIRM < /dev/tty
  fi
  case "$CONFIRM" in
    y|Y|yes|Yes) ;;
    *) die "Da huy cai dat theo yeu cau." ;;
  esac
  curl -fsSL https://get.docker.com | sh || die "Cai Docker that bai. Vui long cai thu cong roi chay lai lenh nay."
  systemctl enable --now docker || true
fi

if [ -d "$INSTALL_DIR" ] && [ ! -w "$INSTALL_DIR" ]; then
  die "Thu muc $INSTALL_DIR da ton tai nhung khong ghi duoc. Kiem tra lai quyen truy cap."
fi
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ===== Buoc 3: tai file cau hinh ban phat hanh =====
say "Tai file cau hinh..."
curl -fsSL "$COMPOSE_URL" -o docker-compose.release.yml || die "Khong tai duoc file cau hinh. Kiem tra ket noi mang."
if [ ! -f .env.example ]; then
  curl -fsSL "$ENV_EXAMPLE_URL" -o .env.example || die "Khong tai duoc file .env.example."
fi

# ===== Buoc 4: sinh .env — AN TOAN KHI CHAY LAI (khong sinh de khoa da co) =====
gen_secret_hex() { openssl rand -hex "$1"; }

if [ -f .env ]; then
  say ".env da ton tai (co the do lan cai dat truoc bi ngat giua chung) — CHI dien bien con thieu, KHONG sinh de khoa cu."
else
  say "Chua co .env — hoi thong tin can thiet, con lai tu sinh."
  : > .env.new
  if [ -n "${INSTALL_BOT_NAME:-}" ]; then
    BOT_NAME_INPUT="$INSTALL_BOT_NAME"
  else
    printf 'Ten hien thi THAT cua bot tren Zalo (vi du: Tro ly ABC): '
    read -r BOT_NAME_INPUT < /dev/tty
  fi
  [ -n "$BOT_NAME_INPUT" ] || die "Ten bot khong duoc de trong."

  if [ -n "${INSTALL_OWNER_UID+x}" ]; then
    OWNER_UID_INPUT="$INSTALL_OWNER_UID"
  else
    printf 'UID Zalo cua chu bot - NEU CHUA BIET, de trong va nhan Enter (se thiet lap sau qua Dashboard): '
    read -r OWNER_UID_INPUT < /dev/tty
  fi

  if [ -n "${INSTALL_DASHBOARD_PASSWORD+x}" ]; then
    DASHBOARD_PASSWORD_INPUT="$INSTALL_DASHBOARD_PASSWORD"
  else
    printf 'Mat khau dang nhap Dashboard - de trong de tu sinh mat khau manh: '
    read -r DASHBOARD_PASSWORD_INPUT < /dev/tty
  fi
  if [ -z "$DASHBOARD_PASSWORD_INPUT" ]; then
    DASHBOARD_PASSWORD_INPUT=$(gen_secret_hex 12)
    say "Da tu sinh mat khau Dashboard, se hien lai o cuoi qua trinh cai dat."
  fi

  touch .env
fi

# Ham: dien 1 bien vao .env NEU chua co dong nao voi ten bien do.
set_if_missing() {
  KEY="$1"; VAL="$2"
  if ! grep -q "^${KEY}=" .env 2>/dev/null; then
    printf '%s=%s\n' "$KEY" "$VAL" >> .env
  fi
}

# Bien nguoi dung vua nhap (chi co gia tri o lan cai dat dau, cac lan sau
# bien tren khong ton tai nen khong ghi de gi ca — dung set_if_missing).
[ -n "${BOT_NAME_INPUT:-}" ] && set_if_missing BOT_NAME "$BOT_NAME_INPUT"
[ -n "${OWNER_UID_INPUT:-}" ] && set_if_missing ZALO_ALLOWED_USERS "$OWNER_UID_INPUT"
[ -n "${DASHBOARD_PASSWORD_INPUT:-}" ] && set_if_missing DASHBOARD_PASSWORD "$DASHBOARD_PASSWORD_INPUT"

# Cac khoa bi mat — CHI sinh neu chua co dong nao (an toan khi chay lai).
set_if_missing INTERNAL_API_TOKEN "$(gen_secret_hex 32)"
set_if_missing ZALO_SCOPED_TOKEN "$(gen_secret_hex 32)"
set_if_missing CONFIDENTIAL_TICKET_SECRET "$(gen_secret_hex 32)"
set_if_missing REDIS_PASSWORD "$(gen_secret_hex 24)"
set_if_missing DASHBOARD_SESSION_SECRET "$(gen_secret_hex 32)"
set_if_missing CREDENTIALS_ENC_KEY "$(gen_secret_hex 32)"
set_if_missing HERMES_DASHBOARD_BASIC_AUTH_USERNAME "hermes_internal"
set_if_missing HERMES_DASHBOARD_BASIC_AUTH_PASSWORD "$(gen_secret_hex 24)"

# Gia tri san production co dinh — luon dam bao dung, khong cho phep sot lai
# gia tri dev nguy hiem tu 1 ban .env cu bi copy nham.
set_if_missing ZALO_CLI_MODE "real"
set_if_missing COOKIE_SECURE "true"
set_if_missing GATEWAY_ALLOW_ALL_USERS "false"
set_if_missing SPEND_CAP_DAILY_USD "0"
set_if_missing OPENROUTER_API_KEY ""
set_if_missing TAVILY_API_KEY ""
set_if_missing OPENROUTER_IMAGE_MODEL ""
set_if_missing DASHBOARD_PASSWORD "$(gen_secret_hex 12)"
set_if_missing ZALO_ALLOWED_USERS ""
set_if_missing BOT_NAME "Bot"

# Kiem tra bat buoc: neu ZALO_ALLOWED_USERS van rong SAU buoc tren, canh
# bao ro (khong chan cai dat — khach co the thiet lap sau qua wizard Phase
# 7 — nhung phai biet no dang mo).
if [ -z "$(grep '^ZALO_ALLOWED_USERS=' .env | cut -d= -f2-)" ]; then
  warn "CHUA thiet lap UID chu bot. Sau khi cai xong, vao Dashboard muc 'Dieu khien Bot' de thiet lap NGAY — neu khong, lenh quan tri/du lieu mat se chua dung duoc cho ai."
fi

chmod 600 .env

# ===== Buoc 5: dang nhap registry + tai image =====
say "Dang nhap kho luu tru va tai image (co the mat vai phut lan dau)..."
# Ten dang nhap luon la tai khoan GitHub cua NGUOI BAN (chu so huu image),
# khong phai cua khach - ma token (GHCR_TOKEN) moi la thu phan biet tung
# don hang, khong phai ten dang nhap.
GHCR_OWNER_USERNAME="${GHCR_NAMESPACE##*/}"
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_OWNER_USERNAME" --password-stdin \
  || die "Ma cai dat khong hop le hoac het han. Lien he nguoi ban de duoc cap lai."

export GHCR_NAMESPACE IMAGE_TAG
docker compose -f docker-compose.release.yml pull || die "Khong tai duoc image. Kiem tra lai ket noi mang va thu lai lenh cai dat."
docker compose -f docker-compose.release.yml up -d || die "Khong khoi dong duoc he thong. Xem log bang: docker compose -f docker-compose.release.yml logs"

# ===== Buoc 6: cho he thong san sang bang tin hieu THAT (khong chi dua vao "healthy") =====
say "Dang cho he thong khoi dong xong (toi da 2 phut)..."
READY=0
i=0
while [ "$i" -lt 24 ]; do
  if docker compose -f docker-compose.release.yml exec -T zalo-gateway \
      node -e "fetch('http://localhost:4001/health').then(r=>r.json()).then(d=>process.exit(d.ok?0:1)).catch(()=>process.exit(1))" >/dev/null 2>&1; then
    READY=1
    break
  fi
  i=$((i + 1))
  sleep 5
done
if [ "$READY" != "1" ]; then
  warn "He thong khoi dong lau hon binh thuong. Kiem tra bang: docker compose -f docker-compose.release.yml logs zalo-gateway"
  warn "Van tiep tuc — co the he thong van dang len, chi la cham."
fi

# ===== Buoc 7: cau hinh tuong lua =====
say "Cau hinh tuong lua (chi mo cong Dashboard 3900 + SSH)..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow 3900/tcp >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
else
  warn "Khong tim thay ufw — bo qua cau hinh tuong lua tu dong. Neu VPS co tuong lua rieng, tu mo cong 3900."
fi

# ===== Ket qua cuoi =====
VPS_IP=$(curl -fsSL -4 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "<IP-VPS-cua-ban>")
DASH_PASS=$(grep '^DASHBOARD_PASSWORD=' .env | cut -d= -f2-)

printf '\n'
printf '================================================================\n'
printf '  CAI DAT HOAN TAT\n'
printf '================================================================\n'
printf '  Dia chi Dashboard:  http://%s:3900\n' "$VPS_IP"
printf '  Mat khau dang nhap: %s\n' "$DASH_PASS"
printf '\n'
printf '  Buoc tiep theo:\n'
printf '  1. Mo dia chi tren bang trinh duyet, dang nhap bang mat khau tren.\n'
printf '  2. Lam theo huong dan tung buoc de: quet QR dang nhap Zalo, nhap\n'
printf '     API key mo hinh AI, nap kien thuc rieng, chon giong dieu.\n'
if [ -z "$(grep '^ZALO_ALLOWED_USERS=' .env | cut -d= -f2-)" ]; then
printf '  3. QUAN TRONG: nhan bat ky tin nhan nao cho bot tren Zalo, roi vao\n'
printf '     Dashboard muc "Dieu khien Bot" de xac nhan minh la chu bot.\n'
fi
printf '================================================================\n\n'
