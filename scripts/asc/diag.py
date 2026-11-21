"""Read-only subscription diagnostics (imported by asc_submit.py when MODE=diag). Prints no secrets/PII."""
import datetime

def run(get, APP_ID, SUB_ID):
    today = datetime.date.today().isoformat()
    for sid in (SUB_ID, "6821011508"):
        print(f"\n######## subscription {sid}")
        s = get(f"/v1/subscriptions/{sid}")
        if not s: continue
        a = s["data"]["attributes"]
        print("  attrs:", {k: a.get(k) for k in ("productId", "name", "state", "subscriptionPeriod", "groupLevel", "familySharable", "availableInAllTerritories")})
        # prices
        pr = get(f"/v1/subscriptions/{sid}/prices", {"include": "territory,subscriptionPricePoint", "limit": 200})
        inc = {(i["type"], i["id"]): i for i in (pr or {}).get("included", [])}
        rows = []
        for p in (pr or {}).get("data", []):
            t = p["relationships"]["territory"]["data"]["id"]
            pp = (p["relationships"].get("subscriptionPricePoint") or {}).get("data")
            ppa = inc.get(("subscriptionPricePoints", pp["id"]), {}).get("attributes", {}) if pp else {}
            rows.append((t, p["attributes"].get("startDate"), p["attributes"].get("preserved"), ppa.get("customerPrice"), pp and pp["id"]))
        cur = [r for r in rows if not r[1] or r[1] <= today]
        fut = [r for r in rows if r[1] and r[1] > today]
        print(f"  prices total={len(rows)} current(start null/past)={len(cur)} future={len(fut)}")
        for r in rows:
            if r[0] in ("USA", "CAN"): print(f"    {r[0]} start={r[1]} preserved={r[2]} customerPrice={r[3]} pricePoint={r[4]}")
        if fut[:3]: print("    sample future:", fut[:3])
        # availability
        av = get(f"/v1/subscriptions/{sid}/subscriptionAvailability")
        if av and av.get("data"):
            at = get(f"/v1/subscriptionAvailabilities/{av['data']['id']}/availableTerritories", {"limit": 200})
            print(f"  availability id={av['data']['id']} newTerritories={av['data']['attributes'].get('availableInNewTerritories')} territories={[x['id'] for x in (at or {}).get('data', [])]}")
        else:
            print("  availability: none")
        # review screenshot (legacy path)
        rs = get(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
        d = rs.get("data") if rs else None
        if d:
            ra = d["attributes"]
            print(f"  reviewScreenshot id={d['id']} file={ra.get('fileName')} size={ra.get('fileSize')} checksum={'set' if ra.get('sourceFileChecksum') else 'none'} imageAsset={'set' if ra.get('imageAsset') else 'none'} delivery={ra.get('assetDeliveryState')}")
        else:
            print("  reviewScreenshot: none")
        # newer subscriptionVersions model (API 4.4.1+), if present
        for path in (f"/v1/subscriptions/{sid}/subscriptionVersions", f"/v1/subscriptions/{sid}/versions"):
            v = get(path, {"limit": 10})
            if v is not None:
                for x in v.get("data", []):
                    print(f"  {path.split('/')[-1]}: id={x['id']} attrs={x.get('attributes')}")
                    for rel in ("appStoreReviewScreenshot", "subscriptionLocalizations", "subscriptionImages"):
                        r = get(f"/v1/subscriptionVersions/{x['id']}/{rel}")
                        if r is not None:
                            dd = r.get("data")
                            n = len(dd) if isinstance(dd, list) else (1 if dd else 0)
                            print(f"     {rel}: {n}" + (f" delivery={(dd.get('attributes') or {}).get('assetDeliveryState')}" if isinstance(dd, dict) and dd else ""))
                break
        locs = get(f"/v1/subscriptions/{sid}/subscriptionLocalizations")
        print(f"  legacy localizations: {[(l['attributes'].get('locale'), l['attributes'].get('state')) for l in (locs or {}).get('data', [])]}")
    print("\nDIAG done (read-only)")
