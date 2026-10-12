"""Decode and verify qualified packed-table bytes shared by Saturn and Pluto."""
import base64
import hashlib


def validate(data, candidate):
    if len(data) != candidate["encodedBytes"]:
        raise ValueError("DE441 binary length differs from the qualified candidate")
    if hashlib.sha256(data).hexdigest() != candidate["sha256"]:
        raise ValueError("DE441 binary digest differs from the qualified candidate")


def extract(source):
    return base64.b64decode(source.split('"""', 2)[1], validate=False)

