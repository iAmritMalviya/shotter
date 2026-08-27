#!/usr/bin/env bash
#
# Create a stable local code-signing identity for Shotter.
#
# Why: with no Apple Developer team, builds are ad-hoc signed and the binary's code-directory
# hash changes on every build. macOS TCC keys the Screen Recording grant on the signing
# identity, so every rebuild silently revoked the permission and capture failed with
# SCStreamErrorDomain -3801. A constant identity keeps the grant across rebuilds.
#
# The key deliberately lives in its own keychain rather than the login keychain. codesign can
# only use a key whose "partition list" permits it, and updating that on the login keychain
# requires the login *keychain* password — which is not always the account password and is
# easily lost. A dedicated keychain has a password we set here, so no prompt and nothing to
# remember. It holds only this disposable signing key and has no authority beyond this machine.
#
# To undo: rm ~/Library/Keychains/shotter-signing.keychain-db, drop it from the search list
# (security list-keychains -d user -s ~/Library/Keychains/login.keychain-db), and revert the
# CODE_SIGN_* settings in project.yml.

set -euo pipefail

NAME="Shotter Local Signing"
KEYCHAIN_FILE="shotter-signing.keychain-db"
KEYCHAIN="$HOME/Library/Keychains/$KEYCHAIN_FILE"
# Not a secret: this keychain contains nothing but a local, disposable code-signing key.
KC_PASS="shotter-local-signing"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Preparing dedicated signing keychain"
if [[ -f "$KEYCHAIN" ]]; then
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
fi
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # no auto-lock timeout
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"

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
# macOS Security framework rejects ("MAC verification failed during PKCS12 import").
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

PW="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/ident.p12" -passout "pass:$PW" -name "$NAME" 2>/dev/null

echo "==> Importing"
security import "$WORK/ident.p12" -k "$KEYCHAIN" -P "$PW" -A -T /usr/bin/codesign

echo "==> Authorising codesign to use the key"
# The step that was failing with errSecInternalComponent. Possible here without a prompt
# because we know this keychain's password.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null

echo "==> Adding to the keychain search list"
EXISTING=()
while IFS= read -r line; do
    EXISTING+=("$(echo "$line" | sed -e 's/^[[:space:]]*"//' -e 's/"$//')")
done < <(security list-keychains -d user)
KEEP=()
for kc in "${EXISTING[@]}"; do
    [[ "$kc" == *"$KEYCHAIN_FILE" ]] || KEEP+=("$kc")
done
security list-keychains -d user -s "${KEEP[@]}" "$KEYCHAIN"

echo "==> Result"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    security find-identity -v -p codesigning | grep "$NAME"
    echo
    echo "Done. Now run:  ./install.sh"
else
    echo "Identity is not listed as valid for code signing; showing all identities:" >&2
    security find-identity -v "$KEYCHAIN" >&2
    exit 1
fi
