"""
list_forms.py   Author: Gorgui Ba Toure

Lists the ONA forms a token can see, to find the form id of a dataset before building its pipeline.
The token is the one named with --token-env (default ONA_API_TOKEN_NIE, read from config/secrets.env or the
environment); it is never printed. Run from the project folder:

    python tools/list_forms.py                                   # Nigeria token, default keywords
    python tools/list_forms.py --search "form a,preparedness"    # your own keywords
    python tools/list_forms.py --token-env ONA_API_TOKEN         # the token of the other countries

Writes data/accessible_forms_<TOKEN_ENV>.csv (every form) and prints the forms whose title / id_string contain a
keyword, or that mention Nigeria, ordered by number of submissions.
"""
import argparse
import os
import sys
from pathlib import Path

import pandas as pd
import requests

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
from _env_loader import load_secrets_env  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--token-env", default="ONA_API_TOKEN_NIE")
ap.add_argument("--search", default="form a,form_a,formulaire a,preparedness,social mob,social_mob,mobilis,mobiliz,acsm")
ap.add_argument("--base", default="https://api.whonghub.org/api/v1")
a = ap.parse_args()

load_secrets_env(HERE)
tok = os.environ.get(a.token_env, "").strip()
if not tok:
    sys.exit(f"[ERROR] {a.token_env} is not set (config/secrets.env)")
H = {"Authorization": f"Token {tok}"}

import time

rows, seen, page, failures = [], set(), 1, 0
while page <= 100 and failures < 3:
    data = None
    for attempt in range(1, 6):                     # the server sometimes answers 502: retry the same page
        try:
            r = requests.get(f"{a.base}/forms.json", headers=H, params={"page": page, "page_size": 500}, timeout=180)
        except requests.RequestException as e:
            print(f"  page {page}: {type(e).__name__}, retry {attempt}/5")
        else:
            if r.status_code == 200:
                data = r.json()
                break
            print(f"  page {page}: HTTP {r.status_code}, retry {attempt}/5")
        time.sleep(5 * attempt)
    if data is None:
        failures += 1
        page += 1
        continue
    failures = 0
    new = [d for d in data if d.get("formid") not in seen]
    if not new:
        break
    for d in new:
        seen.add(d.get("formid"))
        rows.append({k: d.get(k) for k in ("formid", "title", "id_string", "num_of_submissions", "project", "last_submission_time")})
    print(f"  page {page}: {len(new)} forms (total {len(rows)})", flush=True)
    page += 1
df = pd.DataFrame(rows)
out = HERE / "data" / f"accessible_forms_{a.token_env}.csv"
out.parent.mkdir(parents=True, exist_ok=True)
df.to_csv(out, index=False, encoding="utf-8-sig")
print(f"\n{len(df)} forms visible to {a.token_env}; full list saved to {out.relative_to(HERE)}")

words = [w.strip().lower() for w in a.search.split(",") if w.strip()]
txt = (df["title"].astype(str) + " | " + df["id_string"].astype(str) + " | " + df["project"].astype(str)).str.lower()
hit = df[txt.apply(lambda s: any(w in s for w in words))].copy()
hit["num_of_submissions"] = pd.to_numeric(hit["num_of_submissions"], errors="coerce")
pd.set_option("display.width", 250, "display.max_colwidth", 70, "display.max_rows", 200)
print(f"\n{len(hit)} forms match the keywords (most submissions first):")
print(hit.sort_values("num_of_submissions", ascending=False)[["formid", "title", "num_of_submissions", "last_submission_time"]].head(60).to_string(index=False))
