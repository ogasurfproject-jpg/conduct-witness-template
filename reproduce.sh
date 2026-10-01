#!/usr/bin/env bash
# reproduce.sh: recompute HORIZON SHIELD's published NENRIN evidence with the published verifiers, on your machine
# or your runner, and write what you got to receipt.json. Nothing here trusts HORIZON SHIELD's servers: the
# verifiers come from PyPI, the fixtures from a pinned git commit, and every result is recomputed here.
#
#   pip install "nenrin-verify==0.3.0" "a2a-sdk[http-server]==1.2.1" uvicorn     (and node 18+ on the PATH)
#   UPSTREAM=path/to/horizon-shield bash reproduce.sh
set -uo pipefail
UPSTREAM="${UPSTREAM:-upstream}"
E2E="$UPSTREAM/workers/hs-ledger/nenrin/a2a-python-e2e-v0"
OUT="${OUT:-receipt.json}"
LOG=$(mktemp -d)

run() { local name="$1"; shift; ( "$@" ) >"$LOG/$name.txt" 2>&1; echo $? >"$LOG/$name.rc"; }
run selftest nenrin-verify --selftest
run run0002 musubi-verify --run0002
run musubi_selftest musubi-verify --selftest
run e2e_check bash -c "cd '$E2E' && python e2e.py --check"
run e2e_live bash -c "cd '$E2E' && python e2e.py"

LOG="$LOG" UPSTREAM="$UPSTREAM" OUT="$OUT" python3 - <<'PY'
import hashlib, json, os, platform, re, subprocess, sys, datetime
from importlib import metadata
log, up, out = os.environ["LOG"], os.environ["UPSTREAM"], os.environ["OUT"]
def r(name):
    txt = open(os.path.join(log, name + ".txt"), encoding="utf-8", errors="replace").read()
    return {"exit": int(open(os.path.join(log, name + ".rc")).read().strip()), "stdout_sha256": hashlib.sha256(txt.encode()).hexdigest(),
            "last_lines": txt.strip().splitlines()[-6:]}
res = {k: r(k) for k in ["selftest", "run0002", "musubi_selftest", "e2e_check", "e2e_live"]}
m = re.search(r"anchored ([0-9a-f]{64}), settlement ([0-9a-f]{64})", "\n".join(res["run0002"]["last_lines"]))
res["run0002"]["recomputed"] = {"anchored": m.group(1), "settlement": m.group(2)} if m else None
res["e2e_check"]["python_javascript_report_sha256_prefixes"] = re.findall(r"python ([0-9a-f]{12})  javascript ([0-9a-f]{12})", open(os.path.join(log, "e2e_check.txt"), encoding="utf-8").read())
def ver(p):
    try: return metadata.version(p)
    except Exception: return None
try:
    commit = subprocess.run(["git", "-C", up, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip() or None
except Exception:
    commit = None
node = subprocess.run(["node", "--version"], capture_output=True, text=True).stdout.strip()
env = os.environ
receipt = {
    "schema": "nenrin-reproduction-receipt-v0",
    "recomputed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "where": {"repository": env.get("GITHUB_REPOSITORY"), "run_url": (env.get("GITHUB_SERVER_URL", "") + "/" + env.get("GITHUB_REPOSITORY", "") + "/actions/runs/" + env.get("GITHUB_RUN_ID", "")) if env.get("GITHUB_RUN_ID") else None,
              "runner": platform.platform(), "python": platform.python_version(), "node": node},
    "inputs": {"nenrin-verify": ver("nenrin-verify"), "a2a-sdk": ver("a2a-sdk"), "horizon_shield_commit": commit},
    "results": res,
    "all_passed": all(v["exit"] == 0 for v in res.values()),
    "what_this_does_not_establish": "that the evidence is true, only that these published verifiers return these results on this machine; a receipt from the operator's own machine would not count, which is why it lives in your repository",
}
open(out, "w").write(json.dumps(receipt, indent=2) + "\n")
s = os.environ.get("GITHUB_STEP_SUMMARY")
lines = ["## NENRIN reproduction", "", "| check | exit | what came out |", "|---|---|---|"]
for k, v in res.items():
    lines.append("| %s | %d | %s |" % (k, v["exit"], (v["last_lines"][-1] if v["last_lines"] else "").replace("|", "/")[:160]))
lines += ["", "receipt: `%s` sha256 `%s`" % (out, hashlib.sha256(open(out, "rb").read()).hexdigest())]
if s: open(s, "a").write("\n".join(lines) + "\n")
print("\n".join(lines))
sys.exit(0 if receipt["all_passed"] else 1)
PY
