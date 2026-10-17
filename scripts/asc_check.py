"""Checks the App Store Connect API key secrets without printing them.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8. Exits non-zero when the key does not authenticate.
"""
import json, os, re, sys, time, urllib.error, urllib.request
import jwt  # pyjwt[crypto]

key_id, issuer, p8 = (os.environ.get(k, "") for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"))
checks = {
    "ASC_KEY_ID is 10 letters or digits": re.fullmatch(r"[A-Z0-9]{10}", key_id),
    "ASC_ISSUER_ID is a UUID": re.fullmatch(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}", issuer),
    "ASC_KEY_P8 starts with the PEM header": p8.strip().startswith("-----BEGIN PRIVATE KEY-----"),
    "ASC_KEY_P8 ends with the PEM footer": p8.strip().endswith("-----END PRIVATE KEY-----"),
}
for name, ok in checks.items():
    print(("ok   " if ok else "FAIL ") + name)
if key_id != key_id.strip() or issuer != issuer.strip():
    print("FAIL ASC_KEY_ID or ASC_ISSUER_ID has spaces or line breaks around it")


def apps(claims):
    now = int(time.time())
    token = jwt.encode({**claims, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                       p8, algorithm="ES256", headers={"kid": key_id.strip()})
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=de.whnr.klassik",
        headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request) as response:
        return json.load(response)["data"]


try:
    print(f"ok   team key authenticates; apps with bundle ID de.whnr.klassik: {len(apps({'iss': issuer.strip()}))}")
except urllib.error.HTTPError as error:
    print(f"FAIL App Store Connect answered HTTP {error.code} for a team key token: {error.read().decode()[:300]}")
    # An individual key signs without an issuer; Xcode export needs a team key.
    try:
        apps({"sub": "user"})
        print("FAIL the key is an individual key; create a team key (Admin) instead")
    except urllib.error.HTTPError:
        print("FAIL no token shape works: ASC_KEY_P8 does not belong to ASC_KEY_ID, the issuer ID is wrong, or the key is revoked")
    sys.exit(1)
