"""Prints TestFlight feedback (screenshots + crashes) for Klassik from App Store Connect.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (key text). Screenshots land in ./feedback/.
"""
import json, os, time, urllib.request, urllib.parse, pathlib
import jwt  # pyjwt[crypto]

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "de.whnr.klassik"


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})


def get(path, **params):
    url = path if path.startswith("http") else API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def pages(path, **params):
    doc = get(path, **params)
    while True:
        yield doc
        nxt = doc.get("links", {}).get("next")
        if not nxt:
            return
        doc = get(nxt)


def builds(doc):
    return {b["id"]: b["attributes"].get("version") for b in doc.get("included", []) if b["type"] == "builds"}


def header(kind, item, versions):
    a = item["attributes"]
    build = (item.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
    print(f"\n=== {kind} {a.get('createdDate')} build {versions.get(build, '?')} {a.get('deviceModel')} iOS {a.get('osVersion')}")
    print(f"comment: {a.get('comment')!r}")
    print("attributes: " + json.dumps({k: v for k, v in a.items() if k not in ('comment', 'screenshots')}))


TOKEN = token()
app = get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID})["data"][0]["id"]
out = pathlib.Path("feedback")
out.mkdir(exist_ok=True)

for doc in pages(f"/v1/apps/{app}/betaFeedbackScreenshotSubmissions", include="build", limit=50):
    versions = builds(doc)
    for item in doc["data"]:
        header("SCREENSHOT", item, versions)
        for i, shot in enumerate(item["attributes"].get("screenshots") or []):
            name = out / f"{item['attributes']['createdDate'][:19].replace(':', '')}-{i}.png"
            urllib.request.urlretrieve(shot["url"], name)
            print(f"screenshot: {name}")

for doc in pages(f"/v1/apps/{app}/betaFeedbackCrashSubmissions", include="build", limit=50):
    versions = builds(doc)
    for item in doc["data"]:
        header("CRASH", item, versions)
        try:
            log = get(f"/v1/betaFeedbackCrashSubmissions/{item['id']}/crashLog")["data"]["attributes"].get("logText") or ""
            print("crash log (head):\n" + "\n".join(log.splitlines()[:120]))
        except Exception as e:  # crash log may not be processed yet
            print(f"crash log unavailable: {e}")
