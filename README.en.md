# srv-tune — Linux server optimizer

SCAN -> RECOMMEND -> APPLY -> VERIFY -> ROLLBACK-IF-BROKEN.

MVP v0.1: scanner + backup/rollback + CI. Modules (dns/mirror/network/ssh) land in P3.

## Quick start

```bash
./optimizer.sh scan --lang en
./optimizer.sh scan --lang fa
./optimizer.sh recommend
./optimizer.sh status
./optimizer.sh list-backups
```

## Safety

- Every file is backed up before change (manifest in `/var/lib/srv-tune/backups/<id>/`).
- Atomic writes (temp -> validate -> mv). Drop-ins only, never main configs.
- SSH guard: independent timer (`systemd-run` or `nohup` fallback), cancel only via `optimizer confirm <id>` from a NEW session.
- No telemetry. No hidden network calls.

## Docs

- Persian: `README.fa.md`
