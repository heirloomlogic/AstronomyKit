#!/usr/bin/env python3
"""Authenticate a detached checkout against the exact Git tree of its selected revision."""
import hashlib
import os
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def authenticate(checkout, revision):
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip()
    if actual != revision:
        raise ValueError("historical checkout revision changed")
    tree = subprocess.check_output(["git", "ls-tree", "-r", "-z", revision], cwd=checkout)
    identities = {}
    for entry in tree.split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, object_id = metadata.decode().split()
        path = name.decode()
        if kind != "blob":
            raise ValueError("unsupported historical tree entry")
        item = checkout / path
        data = os.readlink(item).encode() if mode == "120000" else item.read_bytes()
        git_hash = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if git_hash != object_id:
            raise ValueError(f"historical tracked file changed: {path}")
        identities[path] = sha(data)
    expected = {p for p in identities if p.startswith("Sources/")}
    found = {str(p.relative_to(checkout)) for p in (checkout / "Sources").rglob("*") if p.is_file()}
    if found != expected:
        raise ValueError("historical source population changed")
    return identities
