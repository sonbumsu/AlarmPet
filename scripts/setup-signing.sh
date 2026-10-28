#!/bin/bash
# Creates a local self-signed code-signing certificate ("NotiPet Dev") in the login keychain.
# build.sh signs with it when present, so the Accessibility permission survives rebuilds.
# Run once per Mac:  ./scripts/setup-signing.sh
set -euo pipefail

NAME="NotiPet Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✅ '$NAME' 인증서가 이미 있어요. 할 일 없음."
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null

PASS=$(/usr/bin/openssl rand -hex 12)
/usr/bin/openssl pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/id.p12" -passout "pass:$PASS" 2>/dev/null

security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "✅ '$NAME' 인증서를 로그인 키체인에 만들었어요."
echo "   처음 빌드할 때 키체인 비밀번호를 묻는 창이 뜨면 맥 로그인 비밀번호를 넣고 '항상 허용'을 누르세요."
