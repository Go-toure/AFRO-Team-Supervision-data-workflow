# AFRO Team Supervision data workflow

Author: Gorgui Ba Toure (WHO AFRO GIS Centre)

Pipeline for the **team supervision** ONA form (Nigeria form **16194**), built like the LQAS / IM / admin pipelines:
Python fetch, R processing, geoname cleaning, quality control, push to the SharePoint *Data Repository* folder, data
dictionary. Nigeria first, **config-driven** so other countries are added by editing `config/forms.csv`.

## What it produces

| File | One row is | Where |
|---|---|---|
| `data/final/afro_team_supervision_repository.csv` | one supervision visit (cleaned, standard state/LGA, indicators 1/0/NA) | local + SharePoint (not in git: large) |
| `data/final/afro_team_supervision_lga_month.csv` | LGA x month x team type x campaign type (counts answered / yes) | git + SharePoint |
| `data/final/afro_team_supervision_indicators_state_month.csv` | state x month x indicator (long, % favourable) | git + SharePoint |
| `data/metadata/AFRO_team_supervision_dictionary.xlsx` | data dictionary (columns, indicators, team types, changelog) | git + SharePoint |
| `reports/qc_summary.json`, `qc_history.csv`, `geo_unmatched.csv` | quality control | local |

**AI agent:** reads these files from the same SharePoint *Data Repository* folder as the LQAS / IM / admin data
(`AFRO_team_supervision_*.csv`, dictionary `AFRO_team_supervision_dictionary.xlsx`) and, locally, from `data/final/`.
The dictionary says what every column and indicator means.

## Tokens (never mixed)

| Country | Variable in `config/secrets.env` |
|---|---|
| Nigeria | `ONA_API_TOKEN_NIE` |
| every other country | `ONA_API_TOKEN` |

Each row of `config/forms.csv` names its token in the column `token_env`. A Nigeria form is only fetched with the
Nigeria token and the other countries only with the other one: there is no fallback from one to the other. Copy
`config/secrets.env.example` to `config/secrets.env` and fill it in (the file is git-ignored; on Windows check that
it is not saved as `secrets.env.txt` -- that name is also accepted).

## Run

```
pip install requests pandas pyarrow
Rscript run_pipeline.r                      # everything
Rscript run_pipeline.r --skip-fetch         # re-process the data already downloaded
Rscript run_pipeline.r --skip-sharepoint-push --skip-qc
Rscript run_pipeline.r --countries NGA      # only some countries in the fetch step
```
Steps: `1 fetch_ona_data.py` -> `2 R/02_process_supervision.R` -> `3 R/03_clean_geonames.R` -> `4 R/05_quality_control.R`
-> `5 R/06_push_to_sharepoint.R`. Each can also be run alone. The fetch and the SharePoint push never stop the pipeline;
the QC never stops it either. R packages: `data.table`, `jsonlite`, `httr`, `writexl` (and `arrow` if you have it,
otherwise python + pyarrow reads the parquet).

## Add a country

1. Add a row to `config/forms.csv` (`form_id, country, iso3, name, token_env, min_date, enabled`); use `ONA_API_TOKEN`
   for any country other than Nigeria.
2. Add its states / districts to the geography list:
   `python tools/build_geo_lookup.py --admin ../AFRO-Dash/input/AFRO_admin_data.rds --countries "ETHIOPIA=ETH"`
   (existing countries are kept).
3. Run the pipeline. Names that could not be matched are listed in `reports/geo_unmatched.csv`; put the right name in
   `data/lookup/geoname_overrides.csv` (`iso3,state_raw,lga_raw,state,lga`) and run again.
If the other country's form has different question names, adapt `R/utils/supervision_indicators.R` (one row per indicator).

## Rules used (summary)

- Repeated submissions of the same ONA record are removed (the latest is kept).
- Visit date = the date typed in the form if plausible (not before `min_date`, not after the submission date + 1 day,
  not more than 60 days before it); otherwise the submission date (`date_source`).
- Indicators: 1 = favourable answer, 0 = other valid answer, NA = blank / not applicable. Lower is better only for
  *evidence of false finger marking* and *evidence of over-tallying*. Percentages = yes / answered.
- Typed numbers outside a plausible range (children sampled 0-500, AFP cases 0-50) become NA and are flagged.
- States / LGAs are standardised with `data/lookup/geo_lookup.csv`; `geo_match` shows how each record was matched.
