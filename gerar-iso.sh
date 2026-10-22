#!/bin/bash
# =====================================================================
#  Gera a ISO própria do Quiosque SMS (Debian 13 live + Firefox)
#  Rode como root numa máquina Debian 13, na mesma pasta onde está o
#  instalar-quiosque.sh JÁ CONFIGURADO (URL_INICIAL, MODO etc.).
#  Uso:  bash gerar-iso.sh
# =====================================================================
set -euo pipefail

# ----------------------- CONFIGURAÇÃO --------------------------------
NOME_ISO="quiosque-sms"
SENHA_ROOT="TroqueEstaSenha"    # senha do root para manutenção (Ctrl+Alt+F2)
NOME_MAQUINA="quiosque-sms"
PASTA_BUILD="/root/quiosque-iso"
# ---------------------------------------------------------------------

[ "$(id -u)" -eq 0 ] || { echo "Execute como root."; exit 1; }

ORIGEM="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_QUIOSQUE="$ORIGEM/instalar-quiosque.sh"
[ -f "$SCRIPT_QUIOSQUE" ] || { echo "Não achei $SCRIPT_QUIOSQUE"; exit 1; }
if grep -q 'COLOQUE-AQUI' "$SCRIPT_QUIOSQUE"; then
    echo "Edite a URL_INICIAL no instalar-quiosque.sh antes de gerar a ISO."; exit 1
fi

LIVRE_GB=$(df -BG --output=avail /root | tail -1 | tr -dc '0-9')
[ "$LIVRE_GB" -ge 8 ] || { echo "Pouco espaço: ${LIVRE_GB} GB livres (precisa de 8 GB)."; exit 1; }

echo ">> Instalando o live-build..."
apt-get update
apt-get install -y live-build

echo ">> Preparando a pasta $PASTA_BUILD..."
if [ -d "$PASTA_BUILD" ]; then (cd "$PASTA_BUILD" && lb clean --purge) || true; fi
rm -rf "$PASTA_BUILD"
mkdir -p "$PASTA_BUILD"
cd "$PASTA_BUILD"

lb config \
    --distribution trixie \
    --archive-areas "main contrib non-free non-free-firmware" \
    --debian-installer none \
    --binary-images iso-hybrid \
    --firmware-binary true \
    --firmware-chroot true \
    --iso-application "Quiosque SMS" \
    --iso-volume "QUIOSQUE_SMS" \
    --bootappend-live "boot=live components quiet locales=pt_BR.UTF-8 keyboard-layouts=br keyboard-model=abnt2 timezone=America/Sao_Paulo hostname=$NOME_MAQUINA live-config.nocomponents=user-setup,sudo,systemd"

echo ">> Lista de pacotes..."
cat > config/package-lists/quiosque.list.chroot <<'EOF'
cage
firefox-esr
firefox-esr-l10n-pt-br
dbus-user-session
libegl-mesa0
libgl1-mesa-dri
fonts-dejavu
fonts-liberation2
locales
keyboard-configuration
console-setup
ca-certificates
network-manager
EOF

echo ">> Ganchos de configuração (usam o seu instalar-quiosque.sh)..."
mkdir -p config/hooks/normal
cp "$SCRIPT_QUIOSQUE" config/hooks/normal/9000-quiosque.hook.chroot
cat > config/hooks/normal/9010-senha-root.hook.chroot <<EOF
#!/bin/bash
echo "root:$SENHA_ROOT" | chpasswd
EOF
chmod 755 config/hooks/normal/9000-quiosque.hook.chroot config/hooks/normal/9010-senha-root.hook.chroot

echo ">> Gerando a ISO (20 a 40 minutos, baixa cerca de 1 GB)..."
lb build 2>&1 | tee build.log

ISO=$(ls -1 "$PASTA_BUILD"/*.iso 2>/dev/null | head -1 || true)
[ -n "$ISO" ] || { echo "A ISO não foi gerada. Veja o final de $PASTA_BUILD/build.log"; exit 1; }

DESTINO="/srv/$NOME_ISO-$(date +%Y%m%d).iso"
cp "$ISO" "$DESTINO"
chmod 644 "$DESTINO"
echo
echo "ISO pronta: $DESTINO ($(du -h "$DESTINO" | cut -f1))"
