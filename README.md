# conduct-witness-template

Press **Use this template**, keep the defaults, and your repository becomes a standing witness: once a day your own GitHub runner walks a few public AI agents and files conduct records those agents did not write. The records are stamped into Bitcoin the next day. No account, no API key, no payment, in either direction.

## What you just did

`.github/workflows/witness.yml` runs [conduct-witness-action](https://github.com/ogasurfproject-jpg/horizon-shield/tree/main/conduct-witness-action) on a schedule. Each run prints a table in the job summary (origin, outcome, record sha256, intake answer) and keeps every record as an artifact in your repository, so your receipt does not depend on anybody's server. Your GitHub name is the witness name unless you change it.

## Make it count more (optional, ten minutes)

Unsigned walks are counted by name. Signed walks are counted under a domain you control:

    openssl genpkey -algorithm ed25519 -out witness.pem
    curl -sSLO https://raw.githubusercontent.com/ogasurfproject-jpg/horizon-shield/main/workers/hs-ledger/nenrin/a2a-conduct-walk/a2a_conduct_walk.py
    python3 a2a_conduct_walk.py --print-public-key witness.pem

Serve the printed JSON at an https URL on your domain, store `witness.pem` as the secret `CONDUCT_WITNESS_KEY`, and uncomment the two lines in the workflow.

## Be walked back

If you run a public A2A agent on your own domain, declare `witness_policy: { reciprocal: true }` in its card's conduct extension ([how](https://github.com/ogasurfproject-jpg/horizon-shield/blob/main/workers/hs-ledger/nenrin/recovery-v0/BECOME_A_WITNESS.md)). Walkers whose own card asks for it are put on the public register and measured back. Nobody is listed without their card saying so, and `listing: decline` in `/.well-known/mcp-conduct.json` stops it at any time.

## What this does not claim

Walking an agent is not endorsing it, and being walked is not a trust badge. A record says what your runner saw, from where, and when. If what you saw disagrees with someone else, both are kept.
