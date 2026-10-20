#!/usr/bin/env bash
#
# asc-api.sh — App Store Connect API helpers shared by provision.sh and
# release.sh. Source it (`. "$SCRIPT_DIR/asc-api.sh"`); don't run it.
#
#   asc_load_credentials    ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH from
#                           ~/.appstoreconnect/ (exits 10 / 11 when missing)
#   asc_make_jwt            ASC_JWT: an ES256 token, good for 20 minutes
#   asc_api METHOD PATH [BODY]
#                           calls https://api.appstoreconnect.apple.com/v1PATH
#                           and prints the response body. Refusals stop the
#                           script with a plain explanation (see below).
#   asc_probe BUNDLE_ID     a read-only GET; returns 0 when the API answers,
#                           21 for a missing agreement, 20 for a refused key,
#                           22 when App Store Connect can't be reached
#   asc_log_mentions_agreement FILE
#                           true when xcodebuild / altool output in FILE is
#                           Apple refusing for want of an accepted agreement
#   asc_explain_agreement   the explanation, on stderr
#
# Exit codes (shared by both scripts):
#   20  App Store Connect refused the API key (401, or a 403 that isn't an
#       agreement)
#   21  a required agreement hasn't been accepted (403
#       FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED, or xcodebuild /
#       altool saying the same)
#   22  App Store Connect couldn't be reached, or answered with an error
#       for a read

ASC_EXIT_AUTH=20
ASC_EXIT_AGREEMENT=21
ASC_EXIT_API=22

asc_load_credentials() {
  local dir="${HOME}/.appstoreconnect"
  if [ ! -f "${dir}/key_id" ] || [ ! -f "${dir}/issuer_id" ]; then
    echo "❌ Missing App Store Connect API credentials:" >&2
    echo "   ${dir}/key_id" >&2
    echo "   ${dir}/issuer_id" >&2
    echo "" >&2
    echo "Set them up with:" >&2
    echo "   mkdir -p ${dir}" >&2
    echo "   echo '<your-key-id>' > ${dir}/key_id" >&2
    echo "   echo '<your-issuer-id>' > ${dir}/issuer_id" >&2
    exit 10
  fi
  ASC_KEY_ID=$(tr -d '[:space:]' < "${dir}/key_id")
  ASC_ISSUER_ID=$(tr -d '[:space:]' < "${dir}/issuer_id")
  ASC_KEY_PATH="${dir}/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  if [ ! -f "$ASC_KEY_PATH" ]; then
    echo "❌ Missing private key: $ASC_KEY_PATH" >&2
    echo "" >&2
    echo "Download AuthKey_${ASC_KEY_ID}.p8 from App Store Connect →" >&2
    echo "Users and Access → Integrations → App Store Connect API, then:" >&2
    echo "   mkdir -p ${dir}/private_keys" >&2
    echo "   mv ~/Downloads/AuthKey_${ASC_KEY_ID}.p8 ${dir}/private_keys/" >&2
    exit 11
  fi
}

# A 20-minute JWT for the App Store Connect API. Apple requires ES256
# (ECDSA over P-256 with SHA-256); the .p8 is that private key. openssl
# signs (DER), Python turns the signature into JOSE's raw r||s form.
asc_make_jwt() {
  ASC_JWT=$(/usr/bin/python3 - "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH" <<'PY'
import sys, json, base64, time, subprocess

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

proc = subprocess.run(
    ["openssl", "dgst", "-sha256", "-sign", p8_path],
    input=signing_input, capture_output=True, check=True,
)
der = proc.stdout

# DER ECDSA-Sig-Value: SEQUENCE { INTEGER r, INTEGER s }
def parse_der_int(buf, i):
    assert buf[i] == 0x02
    ln = buf[i+1]
    return int.from_bytes(buf[i+2:i+2+ln], "big"), i + 2 + ln

assert der[0] == 0x30
cursor = 2 + (der[1] & 0x7F) if der[1] & 0x80 else 2
r, cursor = parse_der_int(der, cursor)
s, _      = parse_der_int(der, cursor)
print(f"{hdr_b64}.{pld_b64}.{b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}")
PY
)
}

asc_explain_agreement() {
  local detail="${1:-}"
  {
    echo ""
    echo "❌ App Store Connect refused the request: a required agreement hasn't"
    echo "   been accepted (HTTP 403, FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED)."
    [ -n "$detail" ] && echo "   Apple said: $detail"
    echo ""
    echo "   Nothing was created, changed or uploaded."
    echo ""
    echo "   Only the team's Account Holder can fix this:"
    echo "   1. https://developer.apple.com/account — accept the updated Apple"
    echo "      Developer Program License Agreement if a banner asks for it."
    echo "   2. https://appstoreconnect.apple.com → Business (Agreements, Tax,"
    echo "      and Banking) — accept any agreement marked pending or expired."
    echo "   Then run this again; the API can take a few minutes to notice."
    echo ""
  } >&2
}

# Apple's first error detail in a JSON body, or nothing.
asc_error_detail() {
  /usr/bin/python3 -c '
import sys, json
try:
    errors = json.load(sys.stdin).get("errors") or []
except Exception:
    sys.exit(0)
if errors:
    e = errors[0]
    print(" — ".join(x for x in (e.get("code"), e.get("title"), e.get("detail")) if x))
' 2>/dev/null || true
}

# Whether a response body is the missing-agreement refusal.
asc_body_is_agreement() {
  grep -Eiq 'REQUIRED_AGREEMENTS|agreement' <<<"$1"
}

asc_api() {
  local method="$1" path="$2" body="${3:-}"
  local out status
  out=$(mktemp)
  local args=(-sS -o "$out" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $ASC_JWT")
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi
  if ! status=$(curl "${args[@]}" "https://api.appstoreconnect.apple.com/v1${path}"); then
    rm -f "$out"
    echo "❌ Couldn't reach App Store Connect ($method $path). Check the network and try again." >&2
    exit "$ASC_EXIT_API"
  fi
  local response
  response=$(cat "$out")
  rm -f "$out"
  case "$status" in
    2??)
      printf '%s' "$response"
      return 0
      ;;
    401)
      echo "❌ App Store Connect refused the API key (HTTP 401) for $method $path." >&2
      echo "   Check ~/.appstoreconnect/key_id, issuer_id and the .p8, and that the key" >&2
      echo "   hasn't been revoked (App Store Connect → Users and Access → Integrations)." >&2
      exit "$ASC_EXIT_AUTH"
      ;;
    403)
      if asc_body_is_agreement "$response"; then
        asc_explain_agreement "$(asc_error_detail <<<"$response")"
        exit "$ASC_EXIT_AGREEMENT"
      fi
      echo "❌ App Store Connect refused $method $path (HTTP 403): $(asc_error_detail <<<"$response")" >&2
      echo "   The API key may lack the role this needs (Admin or App Manager)." >&2
      exit "$ASC_EXIT_AUTH"
      ;;
  esac
  # Any other error. A read can't go on without its answer; a write's caller
  # reads the body and says what failed (as it always has).
  echo "⚠️  App Store Connect answered HTTP $status for $method $path: $(asc_error_detail <<<"$response")" >&2
  if [ "$method" = "GET" ]; then
    exit "$ASC_EXIT_API"
  fi
  printf '%s' "$response"
}

asc_probe() {
  local bundle_id="$1" out status response
  out=$(mktemp)
  if ! status=$(curl -sS -o "$out" -w '%{http_code}' -H "Authorization: Bearer $ASC_JWT" \
      "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=${bundle_id}&limit=1&fields%5Bapps%5D=bundleId"); then
    rm -f "$out"
    return "$ASC_EXIT_API"
  fi
  response=$(cat "$out")
  rm -f "$out"
  case "$status" in
    2??) return 0 ;;
    401) return "$ASC_EXIT_AUTH" ;;
    403)
      if asc_body_is_agreement "$response"; then
        ASC_PROBE_DETAIL=$(asc_error_detail <<<"$response")
        return "$ASC_EXIT_AGREEMENT"
      fi
      return "$ASC_EXIT_AUTH"
      ;;
    *) return "$ASC_EXIT_API" ;;
  esac
}

asc_log_mentions_agreement() {
  grep -Eiq 'PLA Update available|Program License Agreement|REQUIRED_AGREEMENTS|required agreement|agreement (is|has|was) (missing|expired|not)|(accept|sign).{0,40}agreement|agreement.{0,40}(accept|sign)' "$1"
}
