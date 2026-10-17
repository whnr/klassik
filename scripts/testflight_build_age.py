"""Prints the age in whole days of Klassik's newest App Store Connect build.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8. Used by the TestFlight workflow's daily check.
"""
import datetime, json, os, time, urllib.parse, urllib.request
import jwt  # pyjwt[crypto]

API = "https://api.appstoreconnect.apple.com"
now = int(time.time())
token = jwt.encode(
    {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
    os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})


def get(path, **params):
    req = urllib.request.Request(f"{API}{path}?{urllib.parse.urlencode(params)}",
                                 headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


app = get("/v1/apps", **{"filter[bundleId]": "de.whnr.klassik"})["data"][0]["id"]
builds = get("/v1/builds", **{"filter[app]": app, "sort": "-uploadedDate", "limit": 1})["data"]
if not builds:
    print(9999)
else:
    uploaded = datetime.datetime.fromisoformat(builds[0]["attributes"]["uploadedDate"])
    print((datetime.datetime.now(datetime.timezone.utc) - uploaded).days)
