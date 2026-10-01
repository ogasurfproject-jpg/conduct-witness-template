#!/usr/bin/env bash
# setup.sh: one command from nothing to a standing witness that signs, with no domain of your own.
#
#   bash <(curl -sSL https://raw.githubusercontent.com/ogasurfproject-jpg/conduct-witness-template/main/setup.sh) [repo-name]
#
# Needs git, python3 and the GitHub CLI (gh) logged in as you. What it does, in order:
#   1. creates <you>/<repo-name> (default conduct-witness) from this template, public, unless it already exists
#   2. makes an Ed25519 key on this machine with no package at all (RFC 8032 arithmetic, below)
#   3. stores the private key as the repository secret CONDUCT_WITNESS_KEY; the file is deleted when this script ends
#   4. publishes the public key with GitHub Pages at https://<you>.github.io/<repo-name>/conduct-witness-key.json
#      and stores that URL as the repository variable CONDUCT_WITNESS_KEY_URL
#   5. waits until the key is served, then starts both workflows once (NO_RUN=1 skips this)
# From then on your records are signed and counted under <you>.github.io instead of under a name anybody can type.
# Run it again to rotate the key. Nothing is sent to HORIZON SHIELD by this script; your runner files the records.
set -euo pipefail
TEMPLATE="ogasurfproject-jpg/conduct-witness-template"
for c in gh git python3 curl; do command -v "$c" >/dev/null || { echo "needs $c"; exit 1; }; done
gh auth status >/dev/null 2>&1 || { echo "log in first: gh auth login"; exit 1; }
OWNER=$(gh api user --jq .login)
NAME="${1:-conduct-witness}"
REPO="$OWNER/$NAME"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
umask 077

if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "1/5 using your existing repository $REPO"
else
  gh repo create "$REPO" --public --template "$TEMPLATE" >/dev/null
  echo "1/5 created $REPO from the template"
fi
for i in $(seq 1 30); do gh api "repos/$REPO/contents/.github/workflows/witness.yml" >/dev/null 2>&1 && break; sleep 2; done

cat > "$WORK/keygen.py" <<'PY'
# Ed25519 key without any package: RFC 8032 section 5.1.5, the reference arithmetic. Writes witness.pem (PKCS8)
# and pub.json ({"public_key_ed25519_b64": ...}) into the directory given as argv[1].
import base64, hashlib, json, os, sys
p = 2**255 - 19
d = -121665 * pow(121666, p - 2, p) % p
I = pow(2, (p - 1) // 4, p)
def inv(x): return pow(x, p - 2, p)
def xrecover(y):
    xx = (y * y - 1) * inv(d * y * y + 1)
    x = pow(xx, (p + 3) // 8, p)
    if (x * x - xx) % p: x = x * I % p
    return p - x if x % 2 else x
By = 4 * inv(5) % p
Bx = xrecover(By)
B = (Bx, By, 1, Bx * By % p)
def add(P, Q):
    X1, Y1, Z1, T1 = P; X2, Y2, Z2, T2 = Q
    A = (Y1 - X1) * (Y2 - X2) % p; Bv = (Y1 + X1) * (Y2 + X2) % p
    C = T1 * 2 * d * T2 % p; D = Z1 * 2 * Z2 % p
    E, F, G, H = Bv - A, D - C, D + C, Bv + A
    return (E * F % p, G * H % p, F * G % p, E * H % p)
def mul(s, P):
    Q = (0, 1, 1, 0)
    while s:
        if s & 1: Q = add(Q, P)
        P = add(P, P); s >>= 1
    return Q
def public_from_seed(seed):
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little") & ((1 << 254) - 8) | (1 << 254)
    X, Y, Z, _ = mul(a, B)
    zi = inv(Z); x, y = X * zi % p, Y * zi % p
    return (y | ((x & 1) << 255)).to_bytes(32, "little")
if __name__ == "__main__":
    out = sys.argv[1]
    seed = os.urandom(32)
    pem = base64.b64encode(bytes.fromhex("302e020100300506032b657004220420") + seed).decode()
    with open(os.path.join(out, "witness.pem"), "w") as f:
        f.write("-----BEGIN PRIVATE KEY-----\n" + pem + "\n-----END PRIVATE KEY-----\n")
    with open(os.path.join(out, "pub.json"), "w") as f:
        f.write(json.dumps({"public_key_ed25519_b64": base64.b64encode(public_from_seed(seed)).decode()}) + "\n")
PY
python3 "$WORK/keygen.py" "$WORK"
echo "2/5 made an Ed25519 key on this machine (public key $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["public_key_ed25519_b64"])' "$WORK/pub.json"))"

gh secret set CONDUCT_WITNESS_KEY -R "$REPO" < "$WORK/witness.pem"
rm -f "$WORK/witness.pem"
echo "3/5 stored the private key as the secret CONDUCT_WITNESS_KEY; no copy is left on this machine"

gh repo clone "$REPO" "$WORK/repo" -- -q
mkdir -p "$WORK/repo/docs"
cp "$WORK/pub.json" "$WORK/repo/docs/conduct-witness-key.json"
( cd "$WORK/repo" && git add docs/conduct-witness-key.json && { git diff --cached --quiet || git commit -q -m "witness: publish the public key"; } && git push -q origin HEAD )
gh api -X POST "repos/$REPO/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null 2>&1 || true
PAGES=$(gh api "repos/$REPO/pages" --jq .html_url)
KEY_URL="${PAGES%/}/conduct-witness-key.json"
gh variable set CONDUCT_WITNESS_KEY_URL -R "$REPO" --body "$KEY_URL"
echo "4/5 the public key goes to $KEY_URL (repository variable CONDUCT_WITNESS_KEY_URL)"

WANT=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["public_key_ed25519_b64"])' "$WORK/pub.json")
for i in $(seq 1 60); do
  GOT=$(curl -fsS "$KEY_URL" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("public_key_ed25519_b64",""))' 2>/dev/null || true)
  [ "$GOT" = "$WANT" ] && break
  sleep 5
done
if [ "$GOT" != "$WANT" ]; then
  echo "GitHub Pages has not served the key yet. Wait a few minutes, then: gh workflow run witness.yml -R $REPO"
  exit 0
fi
if [ -n "${NO_RUN:-}" ]; then
  echo "5/5 the key is served; NO_RUN is set, so no workflow was started"
else
  gh workflow run witness.yml -R "$REPO"
  gh workflow run reproduce.yml -R "$REPO" 2>/dev/null || true
  echo "5/5 the key is served; both workflows started"
fi
echo
echo "watch:  gh run list -R $REPO --limit 4"
HOST="${KEY_URL#https://}"; HOST="${HOST%%/*}"
echo "your signed records are counted under $HOST"
