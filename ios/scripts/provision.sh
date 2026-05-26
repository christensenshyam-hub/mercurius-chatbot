#!/usr/bin/env bash
#
# provision.sh — bootstrap the Apple Distribution cert + App Store
# provisioning profile for Mercurius via the App Store Connect API.
#
# Why this exists:
#   `xcodebuild archive` with manual signing needs both a Distribution
#   certificate (in Keychain) and a named provisioning profile (in
#   ~/Library/MobileDevice/Provisioning Profiles/) before it'll sign
#   the .app. Xcode's GUI normally creates these interactively, but
#   on a brand-new team with no devices registered and no Xcode
#   sign-in working, we have to provision them via the API instead.
#
#   This is a ONE-TIME setup. Once the cert + profile exist, every
#   future ./scripts/release.sh just reuses them. Certs are valid
#   for 1 year, profiles for ~1 year — script is idempotent and will
#   recreate if missing.
#
# Usage:
#   ./scripts/provision.sh
#
# Requires the same API credentials as release.sh, plus:
#   - openssl    (ships with macOS)
#   - curl       (ships with macOS)
#   - python3    (ships with macOS — used for JSON parsing + JWT signing)

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
IOS_DIR="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

ASC_DIR="${HOME}/.appstoreconnect"
KEY_ID=$(cat "${ASC_DIR}/key_id" | tr -d '[:space:]')
ISSUER_ID=$(cat "${ASC_DIR}/issuer_id" | tr -d '[:space:]')
P8_PATH="${ASC_DIR}/private_keys/AuthKey_${KEY_ID}.p8"

if [ ! -f "$P8_PATH" ]; then
  echo "❌ Missing private key: $P8_PATH"
  exit 1
fi

BUNDLE_ID="com.mayoailiteracy.mercurius.native"
PROFILE_NAME="Mercurius App Store"
TEAM_ID="TMBPRHZYW2"

WORK_DIR="${IOS_DIR}/build/provision"
PROFILES_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$WORK_DIR" "$PROFILES_DIR"

# ---------------------------------------------------------------------------
# Generate a 20-minute JWT for the App Store Connect API.
# Apple's API requires ES256 (ECDSA over P-256 with SHA-256). The .p8 file
# from App Store Connect IS the ECDSA private key. Python does the signing
# because shelling out to openssl produces DER-encoded sigs and JWT needs
# the JOSE "raw" (r||s) form — easier to handle in one place.
# ---------------------------------------------------------------------------
echo "🔑 Generating JWT for App Store Connect API..."
JWT=$(/usr/bin/python3 - "$KEY_ID" "$ISSUER_ID" "$P8_PATH" <<'PY'
import sys, json, base64, time, hashlib, hmac, os, subprocess

key_id, issuer_id, p8_path = sys.argv[1], sys.argv[2], sys.argv[3]

header  = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
payload = {
    "iss": issuer_id,
    "iat": int(time.time()),
    "exp": int(time.time()) + 20 * 60,
    "aud": "appstoreconnect-v1",
}

def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode("ascii")

hdr_b64 = b64url(json.dumps(header,  separators=(",", ":")).encode())
pld_b64 = b64url(json.dumps(payload, separators=(",", ":")).encode())
signing_input = f"{hdr_b64}.{pld_b64}".encode()

# Sign with openssl, get DER ECDSA signature, convert to JOSE raw (r||s).
proc = subprocess.run(
    ["openssl", "dgst", "-sha256", "-sign", p8_path],
    input=signing_input, capture_output=True, check=True,
)
der = proc.stdout

# Parse DER ECDSA-Sig-Value: SEQUENCE { INTEGER r, INTEGER s }
def parse_der_int(buf, i):
    assert buf[i] == 0x02
    ln = buf[i+1]
    return int.from_bytes(buf[i+2:i+2+ln], "big"), i + 2 + ln

assert der[0] == 0x30
# Length may be short or long form
if der[1] & 0x80:
    n = der[1] & 0x7F
    cursor = 2 + n
else:
    cursor = 2
r, cursor = parse_der_int(der, cursor)
s, _      = parse_der_int(der, cursor)
raw_sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
sig_b64 = b64url(raw_sig)

print(f"{hdr_b64}.{pld_b64}.{sig_b64}")
PY
)

# Tiny helper: API GET/POST with auth header. Output goes through `python3 -m json.tool`
# only when piped through `jq_like` to keep it parseable when piped.
api() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -X "$method" \
      -H "Authorization: Bearer $JWT" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "https://api.appstoreconnect.apple.com/v1${path}"
  else
    curl -sS -X "$method" \
      -H "Authorization: Bearer $JWT" \
      "https://api.appstoreconnect.apple.com/v1${path}"
  fi
}

# Tiny JSON helper using python3 stdlib.
json_get() {
  /usr/bin/python3 -c "
import sys, json
data = json.load(sys.stdin)
def dig(d, path):
    for key in path:
        if isinstance(d, list):
            d = d[int(key)]
        else:
            d = d[key]
    return d
print(dig(data, sys.argv[1:]))
" "$@"
}

# ---------------------------------------------------------------------------
# Step 1: Find the bundle ID's resource id (the App Store Connect API uses
# its own UUID for each registered bundle).
# ---------------------------------------------------------------------------
echo "🆔 Looking up bundle id resource for $BUNDLE_ID..."
BUNDLE_RESPONSE=$(api GET "/bundleIds?filter%5Bidentifier%5D=${BUNDLE_ID}&limit=1")
BUNDLE_RID=$(echo "$BUNDLE_RESPONSE" | json_get data 0 id)

if [ -z "$BUNDLE_RID" ] || [ "$BUNDLE_RID" = "None" ]; then
  echo "❌ Bundle id '$BUNDLE_ID' not found in App Store Connect."
  echo "   Make sure step 1 of docs/TESTFLIGHT.md is done."
  exit 2
fi
echo "   → resource id: $BUNDLE_RID"

# ---------------------------------------------------------------------------
# Step 1.5: Set up a dedicated codesigning keychain.
# We do this BEFORE the cert dance so the cert + private key land here
# (where we know the password and can grant codesign access non-
# interactively) instead of in login.keychain (which would prompt for
# the user's macOS password and otherwise error with
# errSecInternalComponent during xcodebuild archive).
# ---------------------------------------------------------------------------
KEYCHAIN_NAME="mercurius-codesign.keychain-db"
KEYCHAIN="${HOME}/Library/Keychains/${KEYCHAIN_NAME}"
KEYCHAIN_PASSWORD="mercurius-ci"

echo "🔐 Preparing dedicated codesigning keychain..."
if [ ! -f "$KEYCHAIN" ]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
fi
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
# Disable the auto-relock timeout so codesign can run minutes from now.
security set-keychain-settings -lut 21600 "$KEYCHAIN"

# Make sure our keychain is on the search path AND the user's login
# keychain is still there too (the search-list set call replaces, not
# appends). Use python so we round-trip the list cleanly.
LIST_KEYCHAINS=$(/usr/bin/python3 -c "
import subprocess, sys
out = subprocess.run(['security', 'list-keychains', '-d', 'user'],
                     capture_output=True, text=True).stdout
items = [l.strip().strip('\"') for l in out.splitlines() if l.strip()]
new = ['$KEYCHAIN'] + [i for i in items if i != '$KEYCHAIN']
print(' '.join(['\"' + i + '\"' for i in new]))
")
eval security list-keychains -d user -s $LIST_KEYCHAINS >/dev/null

# Also nuke any orphaned Apple Distribution cert in the login keychain.
# If one is sitting there (from an earlier provision attempt before we
# introduced the dedicated keychain), codesign might pick it instead of
# ours, and we can't grant it permission to run non-interactively.
LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
if [ -f "$LOGIN_KEYCHAIN" ]; then
  # find-certificate prints both the certificate and (with -a) all matches.
  while IFS= read -r SHA; do
    SHA=$(echo "$SHA" | tr -d '[:space:]')
    [ -z "$SHA" ] && continue
    echo "   → removing stale '$SHA' cert from login.keychain"
    security delete-certificate -Z "$SHA" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true
  done < <(security find-certificate -a -c "Apple Distribution" -Z "$LOGIN_KEYCHAIN" 2>/dev/null | awk -F': ' '/^SHA-1 hash:/ {print $2}')
fi

# ---------------------------------------------------------------------------
# Step 2: Distribution certificate.
# Reuse a remote cert ONLY if our dedicated keychain has the matching
# private key. Otherwise revoke remotely and re-issue locally — we can't
# recover a private key we don't have, so reissuing is the only path.
# ---------------------------------------------------------------------------
echo "📜 Checking for existing Distribution certificate..."
CERTS_RESPONSE=$(api GET "/certificates?filter%5BcertificateType%5D=DISTRIBUTION&limit=200")
EXISTING_CERT_ID=$(echo "$CERTS_RESPONSE" | /usr/bin/python3 -c "
import sys, json
data = json.load(sys.stdin)
# Find first non-expired Distribution cert
import datetime
now = datetime.datetime.now(datetime.timezone.utc)
for c in data.get('data', []):
    exp = c['attributes'].get('expirationDate', '')
    if exp:
        # Apple ISO8601: 2026-05-25T12:00:00.000+0000
        try:
            d = datetime.datetime.strptime(exp, '%Y-%m-%dT%H:%M:%S.%f%z')
        except ValueError:
            d = datetime.datetime.strptime(exp.replace('Z', '+0000'), '%Y-%m-%dT%H:%M:%S%z')
        if d <= now:
            continue
    print(c['id'])
    break
")

CERT_KEY="${WORK_DIR}/dist.key"
CERT_CSR="${WORK_DIR}/dist.csr"
CERT_CER="${WORK_DIR}/dist.cer"
CERT_P12="${WORK_DIR}/dist.p12"
CERT_P12_PASSWORD="mercurius"

if [ -n "$EXISTING_CERT_ID" ] && [ "$EXISTING_CERT_ID" != "None" ]; then
  # Only reuse if OUR dedicated keychain has the matching private key.
  # Checking globally is unreliable — a stale match elsewhere would fool us.
  if security find-identity -v -p codesigning "$KEYCHAIN" | grep -qi "Apple Distribution"; then
    echo "   → reusing cert: $EXISTING_CERT_ID (matched in $KEYCHAIN_NAME)"
    CERT_ID="$EXISTING_CERT_ID"
  else
    echo "   ⚠️  Distribution cert exists on App Store Connect but the private"
    echo "      key isn't in the dedicated keychain. Revoking remote so we can"
    echo "      re-issue one matched to a key we generate here."
    api DELETE "/certificates/${EXISTING_CERT_ID}" >/dev/null
    EXISTING_CERT_ID=""
  fi
fi

if [ -z "${EXISTING_CERT_ID:-}" ] || [ "$EXISTING_CERT_ID" = "None" ]; then
  echo "   → no usable cert found; creating a new one..."

  # 1. Generate an RSA private key + CSR (Apple Distribution certs are RSA-2048).
  openssl genrsa -out "$CERT_KEY" 2048 2>/dev/null
  openssl req -new -key "$CERT_KEY" -out "$CERT_CSR" \
    -subj "/emailAddress=privacy@mercurius.ai/CN=Mercurius Distribution/C=US"

  # 2. Strip PEM headers + newlines so we have just the base64 CSR body
  #    on one line. Apple's /certificates endpoint wants the inner
  #    base64 — NOT the whole PEM re-encoded.
  CSR_B64=$(grep -v -e '-----BEGIN' -e '-----END' "$CERT_CSR" | tr -d '\n')

  # 3. POST /certificates
  CERT_POST_BODY=$(/usr/bin/python3 -c "
import json, sys
print(json.dumps({
  'data': {
    'type': 'certificates',
    'attributes': {
      'certificateType': 'DISTRIBUTION',
      'csrContent': sys.argv[1],
    }
  }
}))" "$CSR_B64")
  CERT_RESPONSE=$(api POST "/certificates" "$CERT_POST_BODY")

  CERT_ID=$(echo "$CERT_RESPONSE" | json_get data id 2>/dev/null || echo "")
  if [ -z "$CERT_ID" ] || [ "$CERT_ID" = "None" ]; then
    echo "❌ Distribution cert creation failed:"
    echo "$CERT_RESPONSE" | /usr/bin/python3 -m json.tool || echo "$CERT_RESPONSE"
    exit 3
  fi
  echo "   → created cert: $CERT_ID"

  # 4. Decode the returned cert content (base64 DER) and import it +
  #    private key into the login keychain as a single .p12 bundle.
  CERT_B64=$(echo "$CERT_RESPONSE" | json_get data attributes certificateContent)
  echo "$CERT_B64" | openssl base64 -d -A > "$CERT_CER"

  openssl x509 -inform DER -in "$CERT_CER" -out "${CERT_CER}.pem"
  openssl pkcs12 -export \
    -inkey "$CERT_KEY" \
    -in "${CERT_CER}.pem" \
    -out "$CERT_P12" \
    -name "Apple Distribution" \
    -password "pass:${CERT_P12_PASSWORD}"

  echo "   → importing cert + key into '$KEYCHAIN_NAME'..."
  security import "$CERT_P12" -k "$KEYCHAIN" -P "$CERT_P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild >/dev/null
  # Critical: let codesign use the private key without a GUI prompt.
  # Without this, archive dies with errSecInternalComponent.
  security set-key-partition-list -S apple-tool:,apple:,codesign:,productbuild: \
    -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Step 3: App Store provisioning profile.
# ---------------------------------------------------------------------------
echo "📝 Checking for existing '$PROFILE_NAME' profile..."
PROFILES_RESPONSE=$(api GET "/profiles?filter%5Bname%5D=${PROFILE_NAME// /%20}&limit=200")
EXISTING_PROFILE_ID=$(echo "$PROFILES_RESPONSE" | /usr/bin/python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('data', []):
    if p['attributes'].get('profileState') == 'ACTIVE' and p['attributes'].get('profileType') == 'IOS_APP_STORE':
        print(p['id'])
        break
")

# Always recreate the profile to make sure it references the current cert.
# (Profiles are cheap, and a stale cert reference here is a common gotcha.)
if [ -n "$EXISTING_PROFILE_ID" ] && [ "$EXISTING_PROFILE_ID" != "None" ]; then
  echo "   → deleting stale profile $EXISTING_PROFILE_ID so we can re-issue"
  api DELETE "/profiles/${EXISTING_PROFILE_ID}" >/dev/null
fi

echo "   → creating new App Store profile..."
PROFILE_POST_BODY=$(/usr/bin/python3 -c "
import json, sys
name, bundle_rid, cert_id = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
  'data': {
    'type': 'profiles',
    'attributes': {
      'name': name,
      'profileType': 'IOS_APP_STORE',
    },
    'relationships': {
      'bundleId':     {'data': {'type': 'bundleIds',    'id': bundle_rid}},
      'certificates': {'data': [{'type': 'certificates','id': cert_id}]},
    }
  }
}))" "$PROFILE_NAME" "$BUNDLE_RID" "$CERT_ID")
PROFILE_RESPONSE=$(api POST "/profiles" "$PROFILE_POST_BODY")

PROFILE_ID=$(echo "$PROFILE_RESPONSE" | json_get data id 2>/dev/null || echo "")
if [ -z "$PROFILE_ID" ] || [ "$PROFILE_ID" = "None" ]; then
  echo "❌ Profile creation failed:"
  echo "$PROFILE_RESPONSE" | /usr/bin/python3 -m json.tool || echo "$PROFILE_RESPONSE"
  exit 4
fi
echo "   → created profile: $PROFILE_ID"

PROFILE_B64=$(echo "$PROFILE_RESPONSE" | json_get data attributes profileContent)
PROFILE_UUID=$(echo "$PROFILE_B64" | openssl base64 -d -A | \
  /usr/bin/security cms -D 2>/dev/null | \
  /usr/bin/python3 -c "
import sys, plistlib
p = plistlib.loads(sys.stdin.buffer.read())
print(p['UUID'])
")

PROFILE_PATH="${PROFILES_DIR}/${PROFILE_UUID}.mobileprovision"
echo "$PROFILE_B64" | openssl base64 -d -A > "$PROFILE_PATH"
echo "   → installed at: $PROFILE_PATH"

# ---------------------------------------------------------------------------
# Done.
# ---------------------------------------------------------------------------
cat <<EOF

────────────────────────────────────────────────────────────
✅  Provisioning complete.

   Distribution cert:    $CERT_ID
   App Store profile:    $PROFILE_NAME ($PROFILE_UUID)

Now run:
   ./scripts/release.sh
────────────────────────────────────────────────────────────
EOF
