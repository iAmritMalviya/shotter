#!/usr/bin/env bash
#
# Create a stable local code-signing identity for Shotter.
#
# Why: with no Apple Developer team, builds are ad-hoc signed and the binary's code-directory
# hash changes on every build. macOS TCC keys the Screen Recording grant on the signing
# identity, so every rebuild silently revokes the permission and capture starts failing with
# SCStreamErrorDomain -3801.
#
# Signing with a self-signed certificate instead gives a constant identity across rebuilds, so
# the grant is given once and sticks. The certificate is local, has no authority beyond this
# machine, and is only usable for code signing.
#
# To undo: delete "Shotter Local Signing" in Keychain Access (login keychain), and revert the
# CODE_SIGN_* settings in project.yml.

set -euo pipefail

NAME="Shotter Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "==> '$NAME' already exists; nothing to do."
    security find-identity -v -p codesigning | grep "$NAME"
    exit 0
fi

echo "==> Generating self-signed code-signing certificate"
cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no

[dn]
CN = $NAME

[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF

# System LibreSSL, not Homebrew OpenSSL 3: the latter writes PKCS#12 with algorithms the
# macOS Security framework cannot read ("MAC verification failed during PKCS12 import").
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# Random one-shot transport password; the bundle is destroyed as soon as it is imported.
PW="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/ident.p12" -passout "pass:$PW" -name "$NAME" 2>/dev/null

echo "==> Importing into the login keychain"
echo "    (macOS may ask for your login password)"
# -A lets codesign use the key without an ACL prompt on every build. This is a disposable
# local signing key, so that convenience is worth more than the per-use prompt.
security import "$WORK/ident.p12" -k "$KEYCHAIN" -P "$PW" -A

echo "==> Trusting it for code signing"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" \
    || echo "    (trust step skipped or declined; signing usually still works)"

echo "==> Result"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    security find-identity -v -p codesigning | grep "$NAME"
    echo
    echo "Done. Now run:  ./install.sh"
else
    echo "error: identity was not created" >&2
    exit 1
fi
