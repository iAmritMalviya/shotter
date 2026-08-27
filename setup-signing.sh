#!/usr/bin/env bash
#
# Create a stable local code-signing identity for Shotter.
#
# Why: with no Apple Developer team, builds are ad-hoc signed and the binary's code-directory
# hash changes on every build. macOS TCC keys the Screen Recording grant on the app's designated
# requirement, so with ad-hoc signing every rebuild silently revoked the permission and capture
# failed with SCStreamErrorDomain -3801. Signing with a fixed certificate makes the requirement
#
#     identifier "com.amrit.Shotter" and certificate leaf = H"..."
#
# which does not change when the code does, so the grant is given once and sticks.
#
# The key deliberately lives in its own keychain rather than the login keychain: codesign can
# only use a key whose keychain "partition list" permits it, and updating that on the login
# keychain requires the login *keychain* password, which is not necessarily the account password.
# This keychain's password is generated here and stored in ~/.config/shotter, mode 600.
#
# To undo: rm ~/Library/Keychains/shotter-signing.keychain-db, drop it from the search list
# (security list-keychains -d user -s ~/Library/Keychains/login.keychain-db), remove
# ~/.config/shotter, and revert the CODE_SIGN_* settings in project.yml.

set -euo pipefail

NAME="Shotter Local Signing"
KEYCHAIN_FILE="shotter-signing.keychain-db"
KEYCHAIN="$HOME/Library/Keychains/$KEYCHAIN_FILE"
PASS_FILE="$HOME/.config/shotter/signing-keychain-password"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

identity_exists() {
    [[ -f "$KEYCHAIN" ]] && security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$NAME"
}

# Regenerating mints a NEW certificate, which changes the designated requirement and therefore
# throws away the Screen Recording grant -- reintroducing exactly the bug this script exists to
# prevent. So an existing identity is left alone unless --force is passed.
if identity_exists && [[ $FORCE -eq 0 ]]; then
    echo "==> '$NAME' already exists; nothing to do."
    security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME"
    echo
    echo "Re-run with --force to regenerate. That issues a new certificate, which will"
    echo "invalidate the existing Screen Recording grant and require granting it again."
    exit 0
fi

if identity_exists && [[ $FORCE -eq 1 ]]; then
    echo "!!  --force: issuing a new certificate. The existing Screen Recording grant will"
    echo "!!  be invalidated and must be granted again after the next ./install.sh."
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Preparing dedicated signing keychain"
mkdir -p "$(dirname "$PASS_FILE")"
chmod 700 "$(dirname "$PASS_FILE")"
KC_PASS="$(/usr/bin/openssl rand -base64 24)"
(umask 077 && printf '%s' "$KC_PASS" > "$PASS_FILE")
chmod 600 "$PASS_FILE"

[[ -f "$KEYCHAIN" ]] && security delete-keychain "$KEYCHAIN" 2>/dev/null || true
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

P12_PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/ident.p12" -passout "pass:$P12_PASS" -name "$NAME" 2>/dev/null

echo "==> Importing"
# -T /usr/bin/codesign rather than -A: only codesign may use the key. TCC now grants screen
# capture to anything signed by this certificate, so the key is a privileged credential --
# it should not be usable by every process on the machine without so much as a prompt.
security import "$WORK/ident.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign

echo "==> Authorising codesign to use the key"
# Without this, signing fails with errSecInternalComponent.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null

echo "==> Adding to the keychain search list"
EXISTING=()
while IFS= read -r line; do
    EXISTING+=("$(echo "$line" | sed -e 's/^[[:space:]]*"//' -e 's/"$//')")
done < <(security list-keychains -d user)
KEEP=()
for kc in "${EXISTING[@]+"${EXISTING[@]}"}"; do
    [[ "$kc" == *"$KEYCHAIN_FILE" ]] || KEEP+=("$kc")
done
# ${arr[@]+"${arr[@]}"} because an empty array under `set -u` is an unbound variable in
# bash 3.2, which is what /bin/bash still is on macOS.
security list-keychains -d user -s ${KEEP[@]+"${KEEP[@]}"} "$KEYCHAIN"

echo "==> Result"
# NOT `find-identity -v`: -v lists only *valid* identities, and this certificate is
# intentionally untrusted (CSSMERR_TP_NOT_TRUSTED), so -v would never list it even though
# codesign signs with it perfectly well. Trusting it would need an admin authorisation dialog.
if security find-identity -p codesigning "$KEYCHAIN" | grep -q "$NAME"; then
    security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME"
    echo
    echo "Done. Now run:  ./install.sh"
else
    echo "error: identity was not created" >&2
    security find-identity -p codesigning "$KEYCHAIN" >&2
    exit 1
fi
