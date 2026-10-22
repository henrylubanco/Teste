#!/bin/bash
# =====================================================================
#  Quiosque SMS - protótipo de "SO" só para navegador
#  Base: Debian 13 mínimo (sem ambiente gráfico) + Cage + Firefox ESR
#  Uso: como root, numa instalação limpa:  bash instalar-quiosque.sh
# =====================================================================
set -euo pipefail

# ----------------------- CONFIGURAÇÃO --------------------------------
URL_INICIAL="https://COLOQUE-AQUI-O-ENDERECO-DO-SISS"

# "navegador" = Firefox em tela cheia COM barra de endereço (navega na internet)
# "quiosque"  = Firefox sem barra nenhuma, preso na URL inicial
MODO="navegador"

USUARIO="quiosque"

# "sim" = apaga histórico, cookies e logins sempre que o navegador reinicia
LIMPAR_AO_SAIR="sim"

# Vazio = internet liberada.
# Para restringir, liste os endereços separados por espaço, ex.:
# SITES_PERMITIDOS="https://siss.exemplo.com.br/* https://*.saude.gov.br/*"
SITES_PERMITIDOS=""
# ---------------------------------------------------------------------

[ "$(id -u)" -eq 0 ] || { echo "Execute como root."; exit 1; }

echo ">> Instalando pacotes..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    cage firefox-esr firefox-esr-l10n-pt-br \
    dbus-user-session libegl-mesa0 libgl1-mesa-dri \
    fonts-dejavu fonts-liberation2 \
    locales keyboard-configuration console-setup ca-certificates

echo ">> Idioma pt_BR..."
sed -i 's/^# *pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=pt_BR.UTF-8

echo ">> Criando usuário $USUARIO..."
if ! id "$USUARIO" &>/dev/null; then
    useradd -m -s /bin/bash -G video,input,render,audio "$USUARIO"
    passwd -l "$USUARIO" >/dev/null   # sem senha: só entra pelo login automático
fi

echo ">> Login automático no tty1..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USUARIO --noclear %I \$TERM
EOF

echo ">> Script de inicialização do navegador..."
cat > /usr/local/bin/iniciar-quiosque <<EOF
#!/bin/bash
export XKB_DEFAULT_LAYOUT=br
export XKB_DEFAULT_MODEL=abnt2
export MOZ_ENABLE_WAYLAND=1

while true; do
    if [ "$LIMPAR_AO_SAIR" = "sim" ]; then
        rm -rf "\$HOME/.mozilla" "\$HOME/.cache/mozilla"
    fi
    if [ "$MODO" = "quiosque" ]; then
        cage -s -- firefox-esr --kiosk "$URL_INICIAL"
    else
        cage -s -- firefox-esr "$URL_INICIAL"
    fi
    sleep 2   # se o navegador fechar ou travar, abre de novo
done
EOF
chmod 755 /usr/local/bin/iniciar-quiosque

PERFIL="/home/$USUARIO/.bash_profile"
cat > "$PERFIL" <<'EOF'
# Abre o navegador automaticamente só no primeiro terminal (tty1)
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec /usr/local/bin/iniciar-quiosque
fi
EOF
chown "$USUARIO:$USUARIO" "$PERFIL"

echo ">> Políticas do Firefox..."
FILTRO=""
if [ -n "$SITES_PERMITIDOS" ]; then
    set -f   # impede o bash de expandir os asteriscos
    LISTA=""
    for s in $SITES_PERMITIDOS; do LISTA+="\"$s\", "; done
    set +f
    FILTRO=",
    \"WebsiteFilter\": { \"Block\": [\"<all_urls>\"], \"Exceptions\": [${LISTA%, }] }"
fi

mkdir -p /usr/lib/firefox-esr/distribution
cat > /usr/lib/firefox-esr/distribution/policies.json <<EOF
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DisableDeveloperTools": true,
    "BlockAboutConfig": true,
    "BlockAboutProfiles": true,
    "DontCheckDefaultBrowser": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "NoDefaultBookmarks": true,
    "PasswordManagerEnabled": false,
    "Homepage": { "URL": "$URL_INICIAL", "Locked": true, "StartPage": "homepage" }$FILTRO
  }
}
EOF

echo ">> Boot mais rápido (menu do GRUB em 1 segundo)..."
if [ -f /etc/default/grub ]; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
    update-grub || true
fi

echo
echo "Pronto. Reinicie com:  reboot"
echo "Manutenção: Ctrl+Alt+F2 abre um terminal; entre como root."
