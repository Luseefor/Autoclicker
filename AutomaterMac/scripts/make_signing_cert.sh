#!/bin/zsh
# Create a stable self-signed code-signing identity ("Automater Dev").
#
# Why: the app is rebuilt constantly, and ad-hoc signatures change identity
# every build — macOS TCC then treats each build as a NEW app and invalidates
# the Accessibility grant. A persistent identity (this cert) keeps the grant
# valid across rebuilds. bundle_app.sh auto-detects and uses it.
set -e

NAME="Automater Dev"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CNF="$WORK/cert.cnf"
PASS="automater-local"

cat > "$CNF" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_req
prompt = no
[dn]
CN = $NAME
[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = CA:false
EOF

echo "→ generating key + certificate…"
openssl req -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -x509 -days 3650 \
  -out "$WORK/cert.pem" -config "$CNF" 2>/dev/null

echo "→ exporting p12…"
openssl pkcs12 -export -out "$WORK/identity.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout "pass:$PASS" 2>/dev/null || true

echo "→ importing into login keychain…"
# macOS security chokes on modern p12 encryption; import PEM directly.
security import "$WORK/key.pem" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "" -A
# -A (allow any app) instead of -T codesign: without a partition-list entry,
# codesign would prompt for the key on EVERY build. For a local self-signed
# dev certificate this trade-off is fine.
security import "$WORK/cert.pem" \
  -k "$HOME/Library/Keychains/login.keychain-db"

echo "→ marking trusted for code signing (user domain)…"
security add-trusted-cert -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  "$WORK/cert.pem"

echo "→ verifying…"
security find-identity -v -p codesigning | grep -F "$NAME" \
  && echo "✅ identity '$NAME' ready — bundle_app.sh will use it automatically" \
  || { echo "❌ identity not found"; exit 1; }
