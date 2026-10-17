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

now = int(time.time())
token = jwt.encode({"iss": issuer.strip(), "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                   p8, algorithm="ES256", headers={"kid": key_id.strip()})
request = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=de.whnr.klassik",
                                 headers={"Authorization": f"Bearer {token}"})
try:
    with urllib.request.urlopen(request) as response:
        apps = json.load(response)["data"]
    print(f"ok   API key authenticates; apps with bundle ID de.whnr.klassik: {len(apps)}")
except urllib.error.HTTPError as error:
    print(f"FAIL App Store Connect answered HTTP {error.code}: {error.read().decode()[:500]}")
    sys.exit(1)
