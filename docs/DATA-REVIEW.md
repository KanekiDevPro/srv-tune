# DATA-REVIEW — manual mirror/resolver review checklist

Every `data/*.list` entry ships with `verified=pending`. Nothing here may be
used by the modules until a human opens the official page, runs the verify
command, and flips that entry to `verified=true`. Automation must NEVER flip
it (`tests/pre-publish.sh` and `release.yml` fail while any entry is pending).

Source honesty: NO entry below was fetched from an official page by the
authoring agent. Every owner/docs URL is written from memory and is itself
unverified — treat the docs column as a lead to check, not a fact.

Legend: `reviewed by` stays empty until a human completes the row.

## DNS resolvers (`data/dns-resolvers.list`)

| # | IP | owner (unverified) | official page to open | verify command | expected result | reviewed by |
|---|---|---|---|---|---|---|
| 1 | 1.1.1.1 (cloudflare, tier default) | Cloudflare | https://1.1.1.1 | `dig +time=2 +tries=1 @1.1.1.1 example.com` | ANSWER section with an `IN A` record |  |
| 2 | 8.8.8.8 (google, tier default) | Google | https://developers.google.com/speed/public-dns | `dig +time=2 +tries=1 @8.8.8.8 example.com` | ANSWER section with an `IN A` record |  |
| 3 | 9.9.9.9 (quad9, tier default) | Quad9 | https://www.quad9.net | `dig +time=2 +tries=1 @9.9.9.9 example.com` | ANSWER section with an `IN A` record |  |
| 4 | 77.88.8.8 (yandex, tier optional) | Yandex | https://dns.yandex.com | `dig +time=2 +tries=1 @77.88.8.8 example.com` | ANSWER section with an `IN A` record |  |
| 5 | 178.22.122.100 (shecan, tier optional) | Shecan | https://shecan.ir | `dig +time=2 +tries=1 @178.22.122.100 example.com` | ANSWER section with an `IN A` record |  |
| 6 | 185.51.200.2 (unknown-owner conflict, tier optional) | UNKNOWN — CONFLICT: was labeled `electrotm`; a third-party README lists this IP as Shecan's secondary DNS. Do NOT guess. | open BOTH https://shecan.ir and https://electrotm.org and compare their published DNS lists | `dig +time=2 +tries=1 @185.51.200.2 example.com` then confirm which operator publishes this IP | Positive operator attribution before any other change |  |
| 7 | ~~electrotm separate entry~~ | REMOVED: folded into row 6. The old `electrotm` label for 185.51.200.2 is unproven. | — | — | — |  |

## APT mirrors (`data/mirrors-debian.list`, `data/mirrors-ubuntu.list`)

| # | URL | owner (unverified) | official page to open | verify command | expected result | reviewed by |
|---|---|---|---|---|---|---|
| 8 | http://deb.debian.org/debian/ (debian-main) | Debian | https://www.debian.org/mirror/ | `curl -sI http://deb.debian.org/debian/dists/stable/InRelease \| head -1` | `HTTP/1.1 200 OK` (or HTTP/2 200) |  |
| 9 | http://mirror.hetzner.com/debian/ (hetzner) | Hetzner | https://mirror.hetzner.com | `curl -sI http://mirror.hetzner.com/debian/dists/stable/InRelease \| head -1` | `HTTP/1.1 200 OK` (or HTTP/2 200) |  |
| 10 | http://ftp.ir.debian.org/debian/ (debian-ir) | Debian | https://www.debian.org/mirror/ | `curl -sI http://ftp.ir.debian.org/debian/dists/stable/InRelease \| head -1` | `HTTP/1.1 200 OK` (or HTTP/2 200) |  |
| 11 | http://archive.ubuntu.com/ubuntu/ (ubuntu-main) | Canonical | https://launchpad.net/ubuntu/+archivemirrors | `curl -sI http://archive.ubuntu.com/ubuntu/dists/noble/InRelease \| head -1` | `HTTP/1.1 200 OK` (or HTTP/2 200) |  |
| 12 | http://ir.archive.ubuntu.com/ubuntu/ (ubuntu-ir) | Canonical | https://launchpad.net/ubuntu/+archivemirrors | `curl -sI http://ir.archive.ubuntu.com/ubuntu/dists/noble/InRelease \| head -1` | `HTTP/1.1 200 OK` (or HTTP/2 200) |  |
| 13 | http://mirror.hetzner.com/ubuntu/ (hetzner) | Hetzner | https://mirror.hetzner.com | `curl -sI http://mirror.hetzner.com/ubuntu/dists/noble/InRelease \| head -1` | `HTTP/1.1 200 OK` (or HTTP/2 200) |  |

## Registry mirrors (`data/mirrors-pip.list`, `data/mirrors-npm.list`, `data/mirrors-docker.list`)

| # | URL | owner (unverified) | official page to open | verify command | expected result | reviewed by |
|---|---|---|---|---|---|---|
| 14 | https://pypi.org/simple/ (pypi-main, official-default) | Python Software Foundation | https://pypi.org | `curl -sI https://pypi.org/simple/ \| head -1` | `HTTP/2 200` |  |
| 15 | https://mirror-pypi.runflare.com/simple/ (runflare-ir, optional) | Runflare | https://runflare.com | `curl -sI https://mirror-pypi.runflare.com/simple/ \| head -1` | `HTTP/2 200` |  |
| 16 | https://registry.npmjs.org/ (npm-main, official-default) | npm Inc | https://docs.npmjs.com/cli/using-npm/config#registry | `curl -sI https://registry.npmjs.org/ \| head -1` | `HTTP/2 200` |  |
| 17 | https://registry.yarnpkg.com/ (yarn-fallback, optional) | Yarn | https://yarnpkg.com/configuration/yarnrc#npmRegistryServer | `curl -sI https://registry.yarnpkg.com/ \| head -1` | `HTTP/2 200` |  |
| 18 | https://registry-1.docker.io/ (docker-main, official-default) | Docker Inc | https://docs.docker.com/engine/daemon/ | `curl -s -o /dev/null -w '%{http_code}' https://registry-1.docker.io/v2/` | `401` (auth challenge realm — the hub answers anonymously with 401, that IS healthy) |  |

## Existence unconfirmed

The entries below may not exist at all (regional mirrors come and go, and
their owner/docs rows are from memory). Existence itself is unverified —
run the exact command and compare before anything else. Never mark verified
on a timeout or an error page: those mean "still unconfirmed", not "dead".

- `http://ftp.ir.debian.org/debian/` — run exactly:
  `curl -sI --max-time 15 http://ftp.ir.debian.org/debian/dists/stable/InRelease | head -1`
  Unconfirmed until this prints a `200` line.
- `http://ir.archive.ubuntu.com/ubuntu/` — run exactly:
  `curl -sI --max-time 15 http://ir.archive.ubuntu.com/ubuntu/dists/noble/InRelease | head -1`
  Unconfirmed until this prints a `200` line.
- `http://mirror.hetzner.com/debian/` — run exactly:
  `curl -sI --max-time 15 http://mirror.hetzner.com/debian/dists/stable/InRelease | head -1`
  Unconfirmed until this prints a `200` line. (Tier already demoted to
  optional: third-party mirrors are never in the default pool.)
- `http://mirror.hetzner.com/ubuntu/` — run exactly:
  `curl -sI --max-time 15 http://mirror.hetzner.com/ubuntu/dists/noble/InRelease | head -1`
  Unconfirmed until this prints a `200` line. (Tier already demoted to
  optional: third-party mirrors are never in the default pool.)

## How to flip an entry

1. Complete the row: open the official page, run the command, compare.
2. Fix owner/docs in the list file if the official page disagrees.
3. Change ONLY that entry's `verified=pending` to `verified=true`.
4. Sign the `reviewed by` cell with name + date.
