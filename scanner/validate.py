#!/usr/bin/env python3
"""Validate a srv-tune scan JSON against schema/scanner-v1.json.

Stdlib only (json/re/sys) so it runs anywhere python3 exists. Enforces the
contract bits that matter: required keys, SCORE numeric 0-100, PROFILE and
OS_TIER enums. Exit 0 valid, 1 with reasons on stderr.
SPDX-License-Identifier: MIT
"""
import json
import re
import sys

SCHEMA_KEYS = (
    "OS_ID OS_VERSION KERNEL INIT VIRT CLOUD_INIT CPU_CORES AES_NI RAM_KB "
    "SWAP_KB DISK_TYPE DISK_FREE_KB IFACE MTU IPV6 CC QDISC DNS MIRROR "
    "PUBLIC_IP SSH_PORT SSH_ROOT SSH_PASS SSH_LISTEN SSH_OK FIREWALL "
    "OPEN_PORTS FAIL2BAN TUNED DOCKER OS_TIER SCORE PROFILE"
).split()
PROFILES = ("generic", "web", "database", "docker", "vpn-tunnel", "low-ram", "custom")
TIERS = ("tier1", "tier2", "best-effort", "eol", "unsupported")


def main(path):
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        print("invalid JSON: %s" % exc)
        return 1
    if not isinstance(doc, dict):
        print("top level must be an object")
        return 1
    bad = False
    for key in SCHEMA_KEYS:
        if key not in doc:
            print("missing key: %s" % key)
            bad = True
    score = doc.get("SCORE", "")
    if not re.fullmatch(r"[0-9]+", str(score)) or not 0 <= int(score) <= 100:
        print("bad SCORE: %r (want 0-100)" % (score,))
        bad = True
    if doc.get("PROFILE") not in PROFILES:
        print("bad PROFILE: %r" % (doc.get("PROFILE"),))
        bad = True
    if doc.get("OS_TIER") not in TIERS:
        print("bad OS_TIER: %r" % (doc.get("OS_TIER"),))
        bad = True
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: validate.py SCAN.json")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
