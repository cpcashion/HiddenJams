#!/usr/bin/env python3
"""Read-only ASC build status poll. GET requests only; never prints secrets."""
import os, sys, time
import jwt, requests

APP_ID = "6756250527"
BUILD = os.environ.get("BUILD_NUMBER", "91")
DEADLINE = time.time() + int(os.environ.get("MAX_WAIT_MIN", "75")) * 60

def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100,
                       "aud": "appstoreconnect-v1"},
                      os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})

def get(path, params):
    r = requests.get("https://api.appstoreconnect.apple.com" + path, params=params,
                     headers={"Authorization": "Bearer " + token()}, timeout=60)
    if r.status_code != 200:
        print(f"GET {path} -> HTTP {r.status_code}")
        return None
    return r.json()

while True:
    d = get("/v1/builds", {"filter[app]": APP_ID, "filter[version]": BUILD,
                           "include": "preReleaseVersion", "limit": 5})
    builds = (d or {}).get("data", [])
    pre = {i["id"]: i for i in (d or {}).get("included", [])}
    if builds:
        b = builds[0]; a = b["attributes"]
        p = b["relationships"]["preReleaseVersion"]["data"]
        mv = pre.get(p["id"], {}).get("attributes", {}).get("version") if p else "?"
        print(f"{time.strftime('%H:%M:%SZ', time.gmtime())} build {BUILD} ({mv}): "
              f"processingState={a.get('processingState')} uploaded={a.get('uploadedDate')} "
              f"usesNonExemptEncryption={a.get('usesNonExemptEncryption')} expired={a.get('expired')}")
        if a.get("processingState") in ("VALID", "FAILED", "INVALID"):
            sys.exit(0 if a.get("processingState") == "VALID" else 1)
    else:
        print(f"{time.strftime('%H:%M:%SZ', time.gmtime())} build {BUILD} not in ASC yet")
    if time.time() > DEADLINE:
        print("timed out waiting"); sys.exit(2)
    time.sleep(60)
