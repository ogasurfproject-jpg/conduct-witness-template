#!/usr/bin/env python3
"""claims.py: recompute HORIZON SHIELD's published price claims on your runner and publish what you got.

For every claim listed at <base>/evidence/claims/index.json this script, with the standard library only:
  1. downloads the dataset (souba-db.json) and computes its SHA-256 itself
  2. checks that the dataset SHA-256 appears in the JIDEC ledger entry the index names (anchored to Bitcoin)
  3. downloads the claim object, recomputes object_sha256 from the canonical JSON, and compares every value row
     with the category of the same id in the dataset it just hashed
  4. downloads the web page the claim belongs to and checks that every yen figure is printed on it
Then it writes docs/claims/receipt.json (machine readable) and docs/claims/index.html (a page on your GitHub
Pages address saying what your runner found, with a link to each page it checked). A mismatch is published as
a mismatch. Nothing is sent to HORIZON SHIELD.

  python3 claims.py                      (env: CLAIMS_BASE to point at another copy, OUT_DIR, default docs/claims)
"""
import datetime, hashlib, html, json, os, sys, urllib.request

BASE = os.environ.get("CLAIMS_BASE", "https://shield.the-horizons-innovation.com").rstrip("/")
SITE = "https://shield.the-horizons-innovation.com"
OUT_DIR = os.environ.get("OUT_DIR", os.path.join("docs", "claims"))
UA = "conduct-witness-claims/0 (+https://github.com/ogasurfproject-jpg/conduct-witness-template)"


def local(url):
    return BASE + url[len(SITE):] if url.startswith(SITE) else url


def get(url):
    req = urllib.request.Request(local(url), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def canon(o):
    return json.dumps(o, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def yen(n):
    return "¥{:,}".format(n)


def check_claim(entry, db_by_id, db_sha):
    res = {"id": entry["id"], "claim_id": entry["claim_id"], "page": entry["page"], "object_url": entry["url"], "checks": {}, "values": []}
    try:
        raw = get(entry["url"])
        obj = json.loads(raw.decode("utf-8"))
    except Exception as e:
        res["checks"]["object_fetched"] = False
        res["error"] = "object: %s" % e
        return res
    res["checks"]["object_fetched"] = True
    body = {k: v for k, v in obj.items() if k != "object_sha256"}
    recomputed = hashlib.sha256(canon(body).encode("utf-8")).hexdigest()
    res["object_sha256_recomputed"] = recomputed
    res["checks"]["object_sha256_matches"] = recomputed == obj.get("object_sha256") == entry.get("object_sha256")
    res["checks"]["object_names_this_dataset"] = obj.get("source", {}).get("dataset_sha256") == db_sha
    rows_ok = True
    for v in obj.get("values", []):
        d = db_by_id.get(v.get("category_id"))
        same = bool(d) and all(d.get(k) == v.get(k) for k in ("work", "unit", "min", "avg", "max"))
        rows_ok = rows_ok and same
        res["values"].append({"category_id": v.get("category_id"), "work": v.get("work"), "unit": v.get("unit"),
                              "min": v.get("min"), "avg": v.get("avg"), "max": v.get("max"), "equals_dataset": same})
    res["checks"]["values_equal_dataset"] = rows_ok and bool(res["values"])
    try:
        page = get(entry["page"]).decode("utf-8", "replace")
        missing = [yen(v[k]) for v in res["values"] for k in ("min", "avg", "max") if v[k] is not None and yen(v[k]) not in page]
        res["checks"]["page_prints_the_figures"] = not missing
        if missing:
            res["page_missing"] = missing
    except Exception as e:
        res["checks"]["page_prints_the_figures"] = False
        res["page_error"] = str(e)
    res["ok"] = all(res["checks"].values())
    return res


def page_html(receipt):
    who = receipt["where"]["repository"] or "this runner"
    rows = []
    for c in receipt["claims"]:
        figs = "<br>".join("%s: %s〜%s (平均 %s) / %s" % (html.escape(v["work"] or ""), yen(v["min"]), yen(v["max"]), yen(v["avg"]), html.escape(v["unit"] or ""))
                           for v in c["values"])
        verdict = "一致 (match)" if c.get("ok") else "不一致 (mismatch): " + html.escape(", ".join(k for k, ok in c["checks"].items() if not ok))
        rows.append("<tr><td><a href=\"%s\">%s</a></td><td>%s</td><td>%s</td><td><a href=\"%s\">object</a><br><code>%s</code></td></tr>"
                    % (html.escape(c["page"]), html.escape(c["page"].replace(SITE, "")), figs, verdict, html.escape(c["object_url"]),
                       html.escape((c.get("object_sha256_recomputed") or "")[:16])))
    return """<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>souba-db price claims recomputed by %(who)s</title>
<meta name="description" content="%(who)s recomputed HORIZON SHIELD's published renovation price claims against the souba-db dataset on %(date)s.">
<style>body{font:15px/1.6 system-ui,sans-serif;max-width:60rem;margin:2rem auto;padding:0 16px;color:#111;background:#fff}
table{border-collapse:collapse;width:100%%}td,th{border-top:1px solid #ccc;padding:.5rem;vertical-align:top;text-align:left}
code{font-size:12px}.wrap{overflow-x:auto}</style></head><body>
<h1>リフォーム費用の公開値を、こちらの runner で再計算した結果</h1>
<p>%(who)s の GitHub runner が %(date)s に、HORIZON SHIELD が公開している工事費の値(souba-db %(ver)s)を自分で取り寄せて確かめました。
データの SHA-256 は <code>%(sha)s</code> で、JIDEC 台帳の <a href="%(anchor)s">記録</a> に%(anchored)s。</p>
<div class="wrap"><table><thead><tr><th>ページ</th><th>公開値</th><th>結果</th><th>再計算した object</th></tr></thead><tbody>
%(rows)s
</tbody></table></div>
<p>確かめたこと: データの hash を自分で計算した / その hash が台帳にある / 値の object の hash を正規化した JSON から計算し直した / object の各行がデータの同じ id の行と一致する / 該当ページに同じ金額が載っている。</p>
<p>確かめていないこと: 値そのものが市場の実態として正しいこと、個別の見積もりが適正かどうか。この表が言えるのは、公開された値が互いに食い違っていないことだけです。</p>
<p>Machine readable: <a href="receipt.json">receipt.json</a> (GitHub attestation: <code>gh attestation verify receipt.json -R %(who)s</code>). Run: %(run)s</p>
</body></html>
""" % {"who": html.escape(who), "date": receipt["recomputed_at"][:10], "ver": html.escape(str(receipt["dataset_version"])),
       "sha": receipt["dataset_sha256_recomputed"], "anchor": html.escape(receipt["anchor"] or ""),
       "anchored": "載っています" if receipt["checks"]["dataset_sha256_in_ledger"] else "載っていません(不一致)",
       "rows": "\n".join(rows), "run": html.escape(receipt["where"]["run_url"] or "local")}


def main():
    idx = json.loads(get(SITE + "/evidence/claims/index.json").decode("utf-8"))
    raw = get(idx["dataset"])
    db_sha = hashlib.sha256(raw).hexdigest()
    db = json.loads(raw.decode("utf-8"))
    db_by_id = {c["id"]: c for c in db.get("categories", [])}
    try:
        in_ledger = db_sha in get(os.environ.get("CLAIMS_ANCHOR") or idx["anchor"]).decode("utf-8", "replace")
    except Exception:
        in_ledger = False
    claims = [check_claim(e, db_by_id, db_sha) for e in idx.get("claims", [])]
    env = os.environ
    receipt = {
        "schema": "souba-claims-receipt-v0",
        "recomputed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "where": {"repository": env.get("GITHUB_REPOSITORY"),
                  "run_url": (env.get("GITHUB_SERVER_URL", "") + "/" + env.get("GITHUB_REPOSITORY", "") + "/actions/runs/" + env.get("GITHUB_RUN_ID", "")) if env.get("GITHUB_RUN_ID") else None},
        "index": SITE + "/evidence/claims/index.json",
        "dataset_version": db.get("_meta", {}).get("version"),
        "dataset_sha256_recomputed": db_sha,
        "anchor": idx.get("anchor"),
        "checks": {"dataset_sha256_matches_index": db_sha == idx.get("dataset_sha256"), "dataset_sha256_in_ledger": in_ledger},
        "claims": claims,
        "what_this_does_not_establish": "that the prices are right for any market or any quote; only that the published figures, the dataset, the ledger entry and the pages agree with each other on this run",
    }
    receipt["all_ok"] = all(receipt["checks"].values()) and bool(claims) and all(c.get("ok") for c in claims)
    os.makedirs(OUT_DIR, exist_ok=True)
    open(os.path.join(OUT_DIR, "receipt.json"), "w", encoding="utf-8").write(json.dumps(receipt, ensure_ascii=False, indent=1) + "\n")
    open(os.path.join(OUT_DIR, "index.html"), "w", encoding="utf-8").write(page_html(receipt))
    lines = ["## price claims recomputed", "", "| claim | result |", "|---|---|"]
    lines += ["| %s | %s |" % (c["id"], "match" if c.get("ok") else "MISMATCH " + ",".join(k for k, ok in c["checks"].items() if not ok)) for c in claims]
    lines += ["", "dataset %s sha256 %s, in ledger: %s" % (receipt["dataset_version"], db_sha[:16], in_ledger)]
    if env.get("GITHUB_STEP_SUMMARY"):
        open(env["GITHUB_STEP_SUMMARY"], "a").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if receipt["all_ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
