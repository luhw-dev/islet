#!/usr/bin/env bash
# Compila e monta Islet.app (o SwiftPM sozinho só gera um binário solto,
# e a gente precisa de um bundle para o LSUIElement e o ícone da barra valerem).
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/Islet.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Islet"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Islet"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Assinar com identidade de desenvolvedor, e não ad-hoc, muda tudo para quem
# depende de permissão: o TCC chaveia pela identidade em vez do hash do binário,
# então Acessibilidade e Monitoramento de Entrada sobrevivem aos rebuilds.
IDENTITY="${ISLET_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Apple Development/ { print $2; exit }')}"

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" "$APP" >/dev/null
else
    echo "aviso: sem identidade de desenvolvedor; assinando ad-hoc (as permissões" >&2
    echo "       vão precisar ser concedidas de novo a cada build)" >&2
    codesign --force --sign - "$APP" >/dev/null
fi

echo "pronto: $APP"
