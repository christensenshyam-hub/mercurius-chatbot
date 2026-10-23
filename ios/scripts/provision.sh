#!/usr/bin/env bash
#
# provision.sh — bootstrap the signing assets for Mercurius via the App
# Store Connect API: the Apple Distribution certificate and the App Store
# provisioning profiles, for the iOS app or (--platform mac) the Mac app.
#
# Why this exists:
#   `xcodebuild archive` with manual signing needs both a Distribution
#   certificate (in Keychain) and a named provisioning profile (in
#   ~/Library/MobileDevice/Provisioning Profiles/) before it'll sign
#   the .app. Xcode's GUI normally creates these interactively, but
#   on a brand-new team with no devices registered and no Xcode
#   sign-in working, we have to provision them via the API instead.
#
#   This is a ONE-TIME setup per platform. Once the certs + profiles exist,
#   every future ./scripts/release.sh just reuses them. Certs are valid
#   for 1 year, profiles for ~1 year — script is idempotent and will
#   recreate if missing.
#
# Usage:
#   ./scripts/provision.sh                    # iOS: Apple Distribution cert,
#                                             # "Mercurius App Store" + widgets profiles
#   ./scripts/provision.sh --platform mac     # Mac: "Mercurius Mac App Store" profile
#                                             # + a Mac Installer Distribution cert
#   ./scripts/provision.sh --check [--platform mac]
#                                             # read-only: what exists, what's
#                                             # missing, what a run would do
#
# The Mac path is additive. It reuses the Apple Distribution certificate the
# iOS path keeps in mercurius-codesign.keychain-db (one certificate signs
# apps for every platform) and never revokes or deletes a certificate; it
# adds the installer certificate the Mac App Store's .pkg is signed with
# ("3rd Party Mac Developer Installer") and a MAC_APP_STORE profile for the
# same bundle id as iOS (universal purchase). Run the iOS path first on a
# machine that has never released.
#
# When App Store Connect refuses because an agreement hasn't been accepted
# (HTTP 403, FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED) the script
# stops at the first request, says so and changes nothing (exit 21).
#
# Requires the same API credentials as release.sh, plus:
#   - openssl    (ships with macOS)
#   - curl       (ships with macOS)
#   - python3    (ships with macOS — used for JSON parsing + JWT signing)

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
IOS_DIR="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

PLATFORM=ios
CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift 2 || { echo "--platform needs ios or mac"; exit 2; } ;;
    --platform=*) PLATFORM="${1#--platform=}"; shift ;;
    --check) CHECK=1; shift ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done
case "$PLATFORM" in
  ios|mac) ;;
  *) echo "Unknown platform '$PLATFORM' (ios or mac)"; exit 2 ;;
esac

# shellcheck source=asc-api.sh
. "${SCRIPT_DIR}/asc-api.sh"
asc_load_credentials
KEY_ID="$ASC_KEY_ID"
ISSUER_ID="$ASC_ISSUER_ID"
P8_PATH="$ASC_KEY_PATH"

BUNDLE_ID="com.mayoailiteracy.mercurius.native"
PROFILE_NAME="Mercurius App Store"
# The widget extension signs separately — its own bundle id + profile.
WIDGET_BUNDLE_ID="com.mayoailiteracy.mercurius.native.MercuriusWidgets"
WIDGET_PROFILE_NAME="Mercurius Widgets App Store"
# The Mac app: the SAME bundle id as iOS (universal purchase), its own
# profile type. The name matches PROVISIONING_PROFILE_SPECIFIER in
# project.yml (MercuriusMac, Release) and ExportOptionsMac.plist.
MAC_PROFILE_NAME="Mercurius Mac App Store"
TEAM_ID="TMBPRHZYW2"

WORK_DIR="${IOS_DIR}/build/provision"
PROFILES_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$WORK_DIR" "$PROFILES_DIR"

KEYCHAIN_NAME="mercurius-codesign.keychain-db"
KEYCHAIN="${HOME}/Library/Keychains/${KEYCHAIN_NAME}"
KEYCHAIN_PASSWORD="${MERCURIUS_KEYCHAIN_PASSWORD:-mercurius-ci}"

# ---------------------------------------------------------------------------
# A 20-minute JWT for the App Store Connect API (asc-api.sh).
# ---------------------------------------------------------------------------
echo "🔑 Generating JWT for App Store Connect API..."
asc_make_jwt
JWT="$ASC_JWT"

# API GET/POST/DELETE with auth (asc-api.sh). A missing agreement, a
# refused key or a failed read stops the script with an explanation.
api() {
  asc_api "$@"
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
# The dedicated codesigning keychain.
# The cert + private key land here (where we know the password and can
# grant codesign access non-interactively) instead of in login.keychain
# (which would prompt for the user's macOS password and otherwise error
# with errSecInternalComponent during xcodebuild archive).
# ---------------------------------------------------------------------------
prepare_keychain() {
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
  local list_keychains
  list_keychains=$(/usr/bin/python3 -c "
import subprocess, sys
out = subprocess.run(['security', 'list-keychains', '-d', 'user'],
                     capture_output=True, text=True).stdout
items = [l.strip().strip('\"') for l in out.splitlines() if l.strip()]
new = ['$KEYCHAIN'] + [i for i in items if i != '$KEYCHAIN']
print(' '.join(['\"' + i + '\"' for i in new]))
")
  eval security list-keychains -d user -s $list_keychains >/dev/null
}

# SHA-1s of the identities in the dedicated keychain whose name contains $1.
keychain_identity_hashes() {
  [ -f "$KEYCHAIN" ] || return 0
  security find-identity -v -p basic "$KEYCHAIN" 2>/dev/null \
    | awk -v want="$1" 'index($0, want) { print $2 }'
}

# The id of the remote certificate of type $1 whose SHA-1 is one of the
# hashes on stdin (the local identities), or nothing.
remote_cert_matching_local() {
  local cert_type="$1" local_hashes response
  local_hashes=$(cat)
  [ -n "$local_hashes" ] || return 0
  response=$(api GET "/certificates?filter%5BcertificateType%5D=${cert_type}&limit=200")
  /usr/bin/python3 -c '
import sys, json, base64, hashlib
data = json.loads(sys.argv[1])
wanted = {h.strip().upper() for h in sys.argv[2].split() if h.strip()}
for c in data.get("data", []):
    content = c["attributes"].get("certificateContent") or ""
    if content and hashlib.sha1(base64.b64decode(content)).hexdigest().upper() in wanted:
        print(c["id"])
        break
' "$response" "$local_hashes"
}

# Path of an installed, unexpired provisioning profile named $1, or nothing.
installed_profile_named() {
  local dir file
  for dir in "${HOME}/Library/MobileDevice/Provisioning Profiles" \
             "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    [ -d "$dir" ] || continue
    for file in "$dir"/*.mobileprovision "$dir"/*.provisionprofile; do
      [ -f "$file" ] || continue
      if security cms -D -i "$file" 2>/dev/null | /usr/bin/python3 -c '
import sys, plistlib, datetime
p = plistlib.loads(sys.stdin.buffer.read())
ok = p.get("Name") == sys.argv[1] and p.get("ExpirationDate", datetime.datetime.max) > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
sys.exit(0 if ok else 1)
' "$1"; then
        echo "$file"
        return 0
      fi
    done
  done
}

# ---------------------------------------------------------------------------
# App Store provisioning profiles. iOS needs two — one for the app, one for
# the widget extension (an appex signs with its own profile); the Mac app
# one, of type MAC_APP_STORE.
# ---------------------------------------------------------------------------
create_and_install_profile() {
  # $3: the profile type (IOS_APP_STORE, or MAC_APP_STORE for the Mac app);
  # $4: the installed file's extension (mobileprovision / provisionprofile).
  local profile_name="$1" bundle_rid="$2"
  local profile_type="${3:-IOS_APP_STORE}" profile_ext="${4:-mobileprovision}"

  echo "📝 Checking for existing '$profile_name' profile..."
  local profiles_response existing_profile_id
  profiles_response=$(api GET "/profiles?filter%5Bname%5D=${profile_name// /%20}&limit=200")
  existing_profile_id=$(echo "$profiles_response" | /usr/bin/python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('data', []):
    if p['attributes'].get('profileState') == 'ACTIVE' and p['attributes'].get('profileType') == sys.argv[1]:
        print(p['id'])
        break
" "$profile_type")

  # Always recreate the profile to make sure it references the current cert.
  # (Profiles are cheap, and a stale cert reference here is a common gotcha.)
  if [ -n "$existing_profile_id" ] && [ "$existing_profile_id" != "None" ]; then
    echo "   → deleting stale profile $existing_profile_id so we can re-issue"
    api DELETE "/profiles/${existing_profile_id}" >/dev/null
  fi

  echo "   → creating new $profile_type profile..."
  local profile_post_body profile_response profile_id
  profile_post_body=$(/usr/bin/python3 -c "
import json, sys
name, bundle_rid, cert_id, profile_type = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
print(json.dumps({
  'data': {
    'type': 'profiles',
    'attributes': {
      'name': name,
      'profileType': profile_type,
    },
    'relationships': {
      'bundleId':     {'data': {'type': 'bundleIds',    'id': bundle_rid}},
      'certificates': {'data': [{'type': 'certificates','id': cert_id}]},
    }
  }
}))" "$profile_name" "$bundle_rid" "$CERT_ID" "$profile_type")
  profile_response=$(api POST "/profiles" "$profile_post_body")

  profile_id=$(echo "$profile_response" | json_get data id 2>/dev/null || echo "")
  if [ -z "$profile_id" ] || [ "$profile_id" = "None" ]; then
    echo "❌ Profile creation failed:"
    echo "$profile_response" | /usr/bin/python3 -m json.tool || echo "$profile_response"
    exit 4
  fi
  echo "   → created profile: $profile_id"

  local profile_b64 profile_uuid
  profile_b64=$(echo "$profile_response" | json_get data attributes profileContent)
  profile_uuid=$(echo "$profile_b64" | openssl base64 -d -A | \
    /usr/bin/security cms -D 2>/dev/null | \
    /usr/bin/python3 -c "
import sys, plistlib
p = plistlib.loads(sys.stdin.buffer.read())
print(p['UUID'])
")

  local profile_path="${PROFILES_DIR}/${profile_uuid}.${profile_ext}"
  echo "$profile_b64" | openssl base64 -d -A > "$profile_path"
  echo "   → installed at: $profile_path"
}

# ---------------------------------------------------------------------------
# --check: read-only. What App Store Connect and this Mac have, and what a
# run would do. Changes nothing (GET requests only, no keychain writes).
# ---------------------------------------------------------------------------
check_only() {
  echo "🔎 Read-only check for the $PLATFORM app (nothing is created or changed)."
  echo ""
  local probe=0
  asc_probe "$BUNDLE_ID" || probe=$?
  case "$probe" in
    0) check_remote ;;
    "$ASC_EXIT_AGREEMENT") asc_explain_agreement "${ASC_PROBE_DETAIL:-}" ;;
    "$ASC_EXIT_AUTH") echo "❌ App Store Connect refused the API key (check ~/.appstoreconnect/)." >&2 ;;
    *) echo "❌ Couldn't reach App Store Connect." >&2 ;;
  esac
  check_local
  return "$probe"
}

check_remote() {
  echo "App Store Connect:"
  local response
  response=$(api GET "/bundleIds?filter%5Bidentifier%5D=${BUNDLE_ID}&limit=1")
  /usr/bin/python3 -c '
import sys, json
d = json.loads(sys.argv[1]).get("data", [])
if d:
    a = d[0]["attributes"]
    ident, platform = a.get("identifier"), a.get("platform")
    print(f"   bundle id {ident}: registered, platform {platform}")
else:
    print(f"   bundle id {sys.argv[2]}: NOT registered")
' "$response" "$BUNDLE_ID"

  local types names name
  if [ "$PLATFORM" = mac ]; then
    types="DISTRIBUTION MAC_INSTALLER_DISTRIBUTION"
    names="$MAC_PROFILE_NAME"
  else
    types="DISTRIBUTION"
    names="$PROFILE_NAME|$WIDGET_PROFILE_NAME"
  fi
  local cert_type
  for cert_type in $types; do
    response=$(api GET "/certificates?filter%5BcertificateType%5D=${cert_type}&limit=200")
    /usr/bin/python3 -c '
import sys, json
d = json.loads(sys.argv[1]).get("data", [])
dates = ", ".join((c["attributes"].get("expirationDate") or "?")[:10] for c in d) or "none"
print(f"   {sys.argv[2]} certificates: {len(d)} (expiring {dates})")
' "$response" "$cert_type"
  done
  local IFS_SAVE="$IFS"
  IFS='|'
  for name in $names; do
    IFS="$IFS_SAVE"
    response=$(api GET "/profiles?filter%5Bname%5D=${name// /%20}&limit=200")
    /usr/bin/python3 -c '
import sys, json
d = json.loads(sys.argv[1]).get("data", [])
rows = []
for p in d:
    a = p["attributes"]
    kind, state, until = a.get("profileType"), a.get("profileState"), (a.get("expirationDate") or "?")[:10]
    rows.append(f"{kind} {state} until {until}")
name = sys.argv[2]
print(f"   profile {name!r}: " + ("; ".join(rows) if rows else "none"))
' "$response" "$name"
    IFS='|'
  done
  IFS="$IFS_SAVE"
  echo ""
}

check_local() {
  echo "This Mac:"
  if [ -f "$KEYCHAIN" ]; then
    echo "   keychain $KEYCHAIN_NAME: present"
  else
    echo "   keychain $KEYCHAIN_NAME: missing (a run creates it)"
  fi
  local dist installer
  dist=$(keychain_identity_hashes "Apple Distribution" | head -1)
  echo "   Apple Distribution identity: ${dist:-none}"
  if [ "$PLATFORM" = mac ]; then
    installer=$( { keychain_identity_hashes "3rd Party Mac Developer Installer"; keychain_identity_hashes "Mac Installer Distribution"; } | head -1)
    echo "   Mac Installer Distribution identity: ${installer:-none (a run creates one)}"
    local installed
    installed=$(installed_profile_named "$MAC_PROFILE_NAME")
    echo "   profile \"$MAC_PROFILE_NAME\": ${installed:-not installed (a run creates and installs it)}"
  else
    local installed
    installed=$(installed_profile_named "$PROFILE_NAME")
    echo "   profile \"$PROFILE_NAME\": ${installed:-not installed}"
    installed=$(installed_profile_named "$WIDGET_PROFILE_NAME")
    echo "   profile \"$WIDGET_PROFILE_NAME\": ${installed:-not installed}"
  fi
}

# ---------------------------------------------------------------------------
# --platform mac: the Mac App Store's signing assets, added beside the iOS
# ones. Never revokes or deletes a certificate.
#   1. The bundle id (the iOS app's — universal purchase).
#   2. The Apple Distribution certificate the iOS path keeps in the
#      dedicated keychain: matched to App Store Connect by its SHA-1.
#   3. A Mac Installer Distribution certificate ("3rd Party Mac Developer
#      Installer: …"), which signs the .pkg the Mac App Store takes:
#      reused from the keychain, else issued from a new key made here.
#   4. The "Mercurius Mac App Store" profile (MAC_APP_STORE), re-issued
#      against the certificate from step 2 and installed as a
#      .provisionprofile.
# ---------------------------------------------------------------------------
provision_mac() {
  echo "🆔 Looking up bundle id resource for $BUNDLE_ID..."
  local response
  response=$(api GET "/bundleIds?filter%5Bidentifier%5D=${BUNDLE_ID}&limit=1")
  BUNDLE_RID=$(echo "$response" | json_get data 0 id 2>/dev/null || echo "")
  if [ -z "$BUNDLE_RID" ] || [ "$BUNDLE_RID" = "None" ]; then
    echo "❌ Bundle id '$BUNDLE_ID' not found in App Store Connect."
    exit 2
  fi
  local bundle_platform
  bundle_platform=$(echo "$response" | json_get data 0 attributes platform 2>/dev/null || echo "?")
  echo "   → resource id: $BUNDLE_RID (platform: $bundle_platform)"
  if [ "$bundle_platform" = "IOS" ]; then
    echo "   ⚠️  App Store Connect lists this bundle id for iOS only. If the profile"
    echo "      below is refused for its platform, open the identifier at"
    echo "      https://developer.apple.com/account/resources/identifiers/list and"
    echo "      make sure macOS is among its platforms, then run this again."
  fi

  prepare_keychain

  echo "📜 Finding the Apple Distribution certificate (shared with iOS)..."
  CERT_ID=$(keychain_identity_hashes "Apple Distribution" | remote_cert_matching_local DISTRIBUTION)
  if [ -z "$CERT_ID" ]; then
    echo "❌ No Apple Distribution certificate in $KEYCHAIN_NAME matches one on"
    echo "   App Store Connect. The iOS path issues it: run ./scripts/provision.sh"
    echo "   (no flags) first, then this again. Nothing was changed."
    exit 3
  fi
  echo "   → reusing cert: $CERT_ID"

  echo "📦 Checking for a Mac Installer Distribution certificate..."
  local installer_hashes installer_id
  installer_hashes=$( { keychain_identity_hashes "3rd Party Mac Developer Installer"; keychain_identity_hashes "Mac Installer Distribution"; } )
  installer_id=$(echo "$installer_hashes" | remote_cert_matching_local MAC_INSTALLER_DISTRIBUTION)
  if [ -n "$installer_id" ]; then
    echo "   → reusing installer cert: $installer_id"
  else
    echo "   → none in $KEYCHAIN_NAME; issuing one..."
    local key="${WORK_DIR}/mac-installer.key" csr="${WORK_DIR}/mac-installer.csr"
    local cer="${WORK_DIR}/mac-installer.cer" p12="${WORK_DIR}/mac-installer.p12"
    local p12_password="mercurius"
    openssl genrsa -out "$key" 2048 2>/dev/null
    openssl req -new -key "$key" -out "$csr" \
      -subj "/emailAddress=privacy@mercurius.ai/CN=Mercurius Mac Installer/C=US"
    local csr_b64 body
    csr_b64=$(grep -v -e '-----BEGIN' -e '-----END' "$csr" | tr -d '\n')
    body=$(/usr/bin/python3 -c "
import json, sys
print(json.dumps({'data': {'type': 'certificates', 'attributes': {
  'certificateType': 'MAC_INSTALLER_DISTRIBUTION', 'csrContent': sys.argv[1]}}}))" "$csr_b64")
    response=$(api POST "/certificates" "$body")
    installer_id=$(echo "$response" | json_get data id 2>/dev/null || echo "")
    if [ -z "$installer_id" ] || [ "$installer_id" = "None" ]; then
      echo "❌ Mac Installer Distribution certificate creation failed:"
      echo "$response" | /usr/bin/python3 -m json.tool || echo "$response"
      echo "   If Apple says the team has too many of these, revoke an unused one at"
      echo "   https://developer.apple.com/account/resources/certificates/list"
      echo "   (this script never revokes certificates), then run this again."
      exit 3
    fi
    echo "   → created installer cert: $installer_id"
    echo "$response" | json_get data attributes certificateContent | openssl base64 -d -A > "$cer"
    openssl x509 -inform DER -in "$cer" -out "${cer}.pem"
    openssl pkcs12 -export -inkey "$key" -in "${cer}.pem" -out "$p12" \
      -name "Mac Installer Distribution" -password "pass:${p12_password}"
    echo "   → importing cert + key into '$KEYCHAIN_NAME'..."
    security import "$p12" -k "$KEYCHAIN" -P "$p12_password" \
      -T /usr/bin/productbuild -T /usr/bin/productsign -T /usr/bin/pkgbuild -T /usr/bin/security >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign:,productbuild: \
      -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true
  fi

  create_and_install_profile "$MAC_PROFILE_NAME" "$BUNDLE_RID" MAC_APP_STORE provisionprofile

  cat <<EOF

────────────────────────────────────────────────────────────
✅  Mac provisioning complete.

   Distribution cert:    $CERT_ID (shared with iOS)
   Installer cert:       $installer_id
   Mac App Store profile: $MAC_PROFILE_NAME

Now run:
   ./scripts/release.sh --platform mac
────────────────────────────────────────────────────────────
EOF
}

if [ "$CHECK" -eq 1 ]; then
  check_status=0
  check_only || check_status=$?
  exit "$check_status"
fi
if [ "$PLATFORM" = mac ]; then
  provision_mac
  exit 0
fi

# ---------------------------------------------------------------------------
# iOS (the default).
# ---------------------------------------------------------------------------
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

# The widget's bundle id we can register ourselves via the API (unlike the
# app's, which carries capabilities configured in the developer portal).
echo "🆔 Looking up bundle id resource for $WIDGET_BUNDLE_ID..."
WIDGET_BUNDLE_RESPONSE=$(api GET "/bundleIds?filter%5Bidentifier%5D=${WIDGET_BUNDLE_ID}&limit=1")
WIDGET_BUNDLE_RID=$(echo "$WIDGET_BUNDLE_RESPONSE" | json_get data 0 id 2>/dev/null || echo "")
if [ -z "$WIDGET_BUNDLE_RID" ] || [ "$WIDGET_BUNDLE_RID" = "None" ]; then
  echo "   → not registered; creating it..."
  WIDGET_BUNDLE_POST=$(/usr/bin/python3 -c "
import json, sys
print(json.dumps({
  'data': {
    'type': 'bundleIds',
    'attributes': {
      'identifier': sys.argv[1],
      'name': 'Mercurius Widgets',
      'platform': 'IOS',
    }
  }
}))" "$WIDGET_BUNDLE_ID")
  WIDGET_BUNDLE_RESPONSE=$(api POST "/bundleIds" "$WIDGET_BUNDLE_POST")
  WIDGET_BUNDLE_RID=$(echo "$WIDGET_BUNDLE_RESPONSE" | json_get data id 2>/dev/null || echo "")
  if [ -z "$WIDGET_BUNDLE_RID" ] || [ "$WIDGET_BUNDLE_RID" = "None" ]; then
    echo "❌ Widget bundle id registration failed:"
    echo "$WIDGET_BUNDLE_RESPONSE" | /usr/bin/python3 -m json.tool || echo "$WIDGET_BUNDLE_RESPONSE"
    exit 2
  fi
fi
echo "   → resource id: $WIDGET_BUNDLE_RID"

# ---------------------------------------------------------------------------
# Step 1.5: Set up the dedicated codesigning keychain.
# We do this BEFORE the cert dance so the cert + private key land there.
# ---------------------------------------------------------------------------
prepare_keychain

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

create_and_install_profile "$PROFILE_NAME" "$BUNDLE_RID"
create_and_install_profile "$WIDGET_PROFILE_NAME" "$WIDGET_BUNDLE_RID"

# ---------------------------------------------------------------------------
# Done.
# ---------------------------------------------------------------------------
cat <<EOF

────────────────────────────────────────────────────────────
✅  Provisioning complete.

   Distribution cert:    $CERT_ID
   App Store profiles:   $PROFILE_NAME, $WIDGET_PROFILE_NAME

Now run:
   ./scripts/release.sh
────────────────────────────────────────────────────────────
EOF
