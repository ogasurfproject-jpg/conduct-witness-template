# conduct-witness-template

Your repository becomes a standing witness: once a day your own GitHub runner walks a few public AI agents and files conduct records those agents did not write, and once a week it recomputes the published evidence itself, including the published renovation price claims, and says on its own Pages address what it found. Records are stamped into Bitcoin the next day. No account, no API key, no payment, in either direction.

## One command

```
bash <(curl -sSL https://raw.githubusercontent.com/ogasurfproject-jpg/conduct-witness-template/main/setup.sh)
```

Needs git, python3 and the GitHub CLI logged in as you (`gh auth login`). It creates `<you>/conduct-witness` from this template, makes an Ed25519 key on your machine (no package needed), stores it as the secret `CONDUCT_WITNESS_KEY`, publishes the public key on your GitHub Pages address, and starts the workflows. Your records are then signed and counted under `<you>.github.io` rather than under a name anybody can type. No domain of your own is needed. Read [setup.sh](setup.sh) before you run it; it is short.

Prefer the button? Press **Use this template**. The witness runs unsigned until you run `setup.sh <your-repo-name>` (it reuses the repository you made) or set the secret and the variable `CONDUCT_WITNESS_KEY_URL` yourself.

## What runs

| workflow | when | what it does | what you keep |
|---|---|---|---|
| `witness.yml` | daily | walks the agents listed in it with [conduct-witness-action](https://github.com/ogasurfproject-jpg/horizon-shield/tree/main/conduct-witness-action) and files the records, signed when the key is set | the records as an artifact, a table in the job summary |
| `reproduce.yml` | weekly | installs the published verifiers (`pip install nenrin-verify`, npm's `nenrin_verify.mjs`) and recomputes the published evidence: 31 provenance bundles and 98 TSUGI chains against the JavaScript, MUSUBI's 18 self-tests and run0002, and one A2A task run live through the official A2A Python SDK | `receipt.json`, and a GitHub attestation of it under your repository's identity |
| `claims.yml` | weekly | runs [claims.py](claims.py): downloads HORIZON SHIELD's renovation price dataset and hashes it, checks the hash is in the Bitcoin-anchored ledger entry, recomputes each published price claim object, compares every value with the dataset and checks the same yen figures are printed on the page the claim belongs to | `docs/claims/receipt.json` attested under your repository, and a page at `https://<you>.github.io/<repo>/claims/` that says what your runner found, match or mismatch |

Anyone can check a receipt without trusting you or us:

```
gh attestation verify receipt.json -R <you>/conduct-witness
```

The point of a receipt is where it was made. One from the operator's own machine proves little; one from yours, with your repository's signature on it, is the kind of evidence a protocol needs.

## Be walked back

If you run a public A2A agent on your own domain, declare `witness_policy: { reciprocal: true }` in its card's conduct extension ([how](https://github.com/ogasurfproject-jpg/horizon-shield/blob/main/workers/hs-ledger/nenrin/recovery-v0/BECOME_A_WITNESS.md)). Walkers whose own card asks for it are put on the public register and measured back. Nobody is listed without their card saying so, and `listing: decline` in `/.well-known/mcp-conduct.json` stops it at any time.

## Credit

Your signed records can be credited by name in the NENRIN citation metadata (the Zenodo DOI record and CITATION.cff), only if you ask for it and under the name you choose: [WITNESSES.md](https://github.com/ogasurfproject-jpg/horizon-shield/blob/main/workers/hs-ledger/nenrin/WITNESSES.md).

## What this does not claim

Walking an agent is not endorsing it, and being walked is not a trust badge. A record says what your runner saw, from where, and when. A signature under `<you>.github.io` says which GitHub account signed, not that the account is independent of anyone; a GitHub account is cheap, and the ledger caps records per domain for that reason. If what you saw disagrees with someone else, both are kept.
