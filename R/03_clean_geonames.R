# ============================================================
# 03_clean_geonames.R   (step 3 of run_pipeline.r)
# Author: Gorgui Ba Toure
#
# Takes data/processed/supervision_clean.csv and
#   1. gives every record the STANDARD state and LGA name (the same names as the AFRO administrative data), using
#        a) data/lookup/geoname_overrides.csv    manual corrections (iso3, state_raw, lga_raw, state, lga) -- always win
#        b) data/lookup/geo_aliases.csv           state spellings (iso3, alias, state), e.g. FCT ABUJA -> FCT
#        c) exact match on letters+digits only    ("Dange-Shuni" = "DANGE SHUNI")
#        d) fuzzy match inside the same state     (edit distance <= 1 per 5 letters, only when ONE best candidate)
#      geo_match says how each record was matched: override / exact / fuzzy / state_only / unmatched. Names that
#      could not be matched are kept as typed and listed in reports/geo_unmatched.csv: add them to
#      geoname_overrides.csv and re-run -- nothing else to change.
#   2. writes the final tables (data/final/)
#        afro_team_supervision_repository.csv            one row per supervision visit (large: not tracked in git)
#        afro_team_supervision_lga_month.csv             LGA x month x team type x campaign type, counts of answers
#        afro_team_supervision_indicators_state_month.csv  state x month x indicator, % favourable (long format)
#   3. writes the data dictionary (data/metadata/AFRO_team_supervision_dictionary.xlsx and ..._columns.csv) with a
#      changelog against the previous run's columns.
# The geography list is data/lookup/geo_lookup.csv (built by tools/build_geo_lookup.py).
# ============================================================
suppressPackageStartupMessages({ library(data.table) })
source("R/utils/helpers.R"); source("R/utils/supervision_indicators.R")
STEP <- "03_clean_geonames"
for (d in c("data/final", "data/metadata", "data/lookup", "reports")) dir.create(d, showWarnings = FALSE, recursive = TRUE)

IN_FILE <- "data/processed/supervision_clean.csv"
if (!file.exists(IN_FILE)) { log_msg(STEP, "FAILED: ", IN_FILE, " not found -- run step 2 first."); quit(status = 1) }
dt <- fread(IN_FILE, colClasses = list(character = c("record_id", "team_code", "state_raw", "lga_raw", "ward")), encoding = "UTF-8")
log_msg(STEP, "Read ", format(nrow(dt), big.mark = ","), " records")

# ---------------------------------------------------------------- geography (R/utils/geo_match.R)
source("R/utils/geo_match.R")
dt <- standardise_geo(dt, STEP)

# ---------------------------------------------------------------- final visit-level repository
ind_cols <- paste0("ind_", SUP_INDICATORS$id)
front <- c("country", "iso3", "form_id", "record_id", "visit_date", "date_source", "year", "month", "epi_week",
           "state", "lga", "ward", "geo_match", "state_raw", "lga_raw", "settlement", "settlement_type",
           "supervision_type", "team_type", "sup_level", "campaign_type", "antigen", "camp_day", "agency",
           "supervisor_designation", "supervisor_gender", "team_code", "submission_time", "lat", "lon", "gps_valid")
rest <- c(ind_cols, "children_sampled", "not_fully_marked_sampled", "afp_cases_reported", "flag_number_outlier")
repo <- dt[, c(front, rest), with = FALSE]
setorder(repo, iso3, visit_date, state, lga)
fwrite(repo, "data/final/afro_team_supervision_repository.csv", na = "")
log_msg(STEP, "Wrote data/final/afro_team_supervision_repository.csv (", format(nrow(repo), big.mark = ","), " rows)")

# ---------------------------------------------------------------- summary tables
repo[, h2h_records := as.integer(team_type == "H2H")]
keys <- c("country", "iso3", "state", "lga", "month", "supervision_type", "campaign_type")
lm <- repo[, .(records = .N, h2h_records = sum(h2h_records),
               children_sampled_total = sum(children_sampled, na.rm = TRUE),
               not_fully_marked_total = sum(not_fully_marked_sampled, na.rm = TRUE),
               afp_cases_reported_total = sum(afp_cases_reported, na.rm = TRUE)), by = keys]
for (id in SUP_INDICATORS$id) {
  col <- paste0("ind_", id)
  t <- repo[, .(a = sum(!is.na(get(col))), y = sum(get(col), na.rm = TRUE)), by = keys]
  setnames(t, c("a", "y"), paste0(id, c("_answered", "_yes")))
  lm <- merge(lm, t, by = keys, sort = FALSE)
}
setorder(lm, iso3, state, lga, month, supervision_type, campaign_type)
fwrite(lm, "data/final/afro_team_supervision_lga_month.csv", na = "")
log_msg(STEP, "Wrote data/final/afro_team_supervision_lga_month.csv (", format(nrow(lm), big.mark = ","), " rows)")

long <- rbindlist(lapply(seq_len(nrow(SUP_INDICATORS)), function(k) {
  ind <- SUP_INDICATORS[k]; col <- paste0("ind_", ind$id)
  repo[, .(indicator_id = ind$id, indicator = ind$label, team_group = ind$group, lower_is_better = ind$lower_is_better,
           answered = sum(!is.na(get(col))), yes = sum(get(col), na.rm = TRUE)), by = .(country, iso3, state, month)]
}))
long[, pct_yes := fifelse(answered > 0, round(100 * yes / answered, 1), NA_real_)]
setorder(long, iso3, state, month, indicator_id)
fwrite(long[answered > 0], "data/final/afro_team_supervision_indicators_state_month.csv", na = "")
log_msg(STEP, "Wrote data/final/afro_team_supervision_indicators_state_month.csv (", format(nrow(long[answered > 0]), big.mark = ","), " rows)")

# ---------------------------------------------------------------- data dictionary
desc <- c(
  country = "Country name (config/forms.csv)", iso3 = "ISO3 country code", form_id = "ONA form id the record comes from",
  record_id = "ONA record id (_id); unique per visit", visit_date = "Date of the supervision visit (see date_source)",
  date_source = "form = date typed in the form was plausible; submission_time = replaced by the ONA submission date",
  year = "Year of visit_date", month = "Month of visit_date (YYYY-MM)", epi_week = "ISO week of visit_date (YYYY-Www)",
  state = "Standard state name (AFRO administrative data)", lga = "Standard LGA / district name (AFRO administrative data)",
  ward = "Ward as typed in the form (upper case, not standardised)", geo_match = "How state/LGA were matched: override, exact, fuzzy, state_only, unmatched",
  state_raw = "State as typed in the form", lga_raw = "LGA as typed in the form", settlement = "Settlement as typed in the form",
  settlement_type = "Settlement type (urban, rural village, ...)", supervision_type = "Type of team supervised (readable label)",
  team_type = "Short code: H2H, H2H_TFP, FP, SPECIAL", sup_level = "Level of the supervisor (ward, lga, state, national, zonal)",
  campaign_type = "Campaign type (ipdstype: SNIPDS, NIPDS, OBR, IBRA, ...)", antigen = "Antigen(s) of the campaign",
  camp_day = "Campaign day (D1..D4, Mop_up_1, ...)", agency = "Agency of the supervisor", supervisor_designation = "Designation of the supervisor",
  supervisor_gender = "Gender of the supervisor", team_code = "Team code typed in the form", submission_time = "ONA submission time (UTC)",
  lat = "Latitude of the visit (NA when invalid)", lon = "Longitude of the visit (NA when invalid)",
  gps_valid = "TRUE when the form GPS point is within range and not 0/0",
  children_sampled = "H2H: children sampled by the supervisor (0-500, else NA)",
  not_fully_marked_sampled = "H2H: sampled children not fully marked (0-500 and <= children_sampled, else NA)",
  afp_cases_reported = "H2H: AFP cases reported by the team (0-50, else NA)",
  flag_number_outlier = "TRUE when one of the three numbers above was outside its plausible range and set to NA"
)
cols <- data.table(column = names(repo), type = vapply(repo, function(x) class(x)[1], character(1)))
cols[, description := desc[column]]
ii <- match(cols$column, ind_cols)
cols[!is.na(ii), description := paste0("Indicator '", SUP_INDICATORS$label[ii[!is.na(ii)]], "': 1 = ",
        ifelse(SUP_INDICATORS$lower_is_better[ii[!is.na(ii)]], "evidence found (lower is better)", "favourable answer"),
        ", 0 = other valid answer, NA = blank/not applicable. Asked only of ", SUP_INDICATORS$group[ii[!is.na(ii)]], " teams.")]
cols[is.na(description), description := ""]
cols[, file := "afro_team_supervision_repository.csv"]
fwrite(cols, "data/metadata/AFRO_team_supervision_dictionary_columns.csv")

ind_doc <- copy(SUP_INDICATORS)[, .(indicator_id = id, indicator = label, team_group = group, source_question = source,
                                    favourable_answers = favourable, valid_answers = valid, lower_is_better)]
sum_cols <- data.table(
  table = c("afro_team_supervision_repository.csv", "afro_team_supervision_lga_month.csv", "afro_team_supervision_indicators_state_month.csv"),
  one_row_is = c("one supervision visit", "LGA x month x team type x campaign type (counts: <indicator>_answered and <indicator>_yes; % = yes / answered)",
                 "state x month x indicator (answered, yes, pct_yes)"))
prev_file <- "data/metadata/schema_previous.csv"
cur <- data.table(column = names(repo))
chg <- if (file.exists(prev_file)) {
  prev <- fread(prev_file)
  rbind(data.table(change = "added", column = setdiff(cur$column, prev$column)),
        data.table(change = "removed", column = setdiff(prev$column, cur$column)))
} else data.table(change = "first run", column = cur$column)
if (nrow(chg) == 0) chg <- data.table(change = "no change", column = "")
chg[, run_date := as.character(Sys.Date())]
fwrite(cur, prev_file)
about <- data.table(item = c("Pipeline", "Author", "Source", "Records", "Generated", "Reading note"),
  value = c("AFRO-Team-Supervision-data-workflow", "Gorgui Ba Toure", "ONA form(s) listed in config/forms.csv",
            format(nrow(repo), big.mark = ","), format(Sys.time(), "%Y-%m-%d %H:%M"),
            "Percentages = yes / answered. Not-applicable and blank answers are not counted. Lower is better only for evidence_ffm and evidence_overtally."))
if (requireNamespace("writexl", quietly = TRUE)) {
  writexl::write_xlsx(list(About = about, Tables = sum_cols, Columns = cols, Indicators = ind_doc,
                           Supervision_types = SUP_TYPES, Changelog = chg),
                      "data/metadata/AFRO_team_supervision_dictionary.xlsx")
  log_msg(STEP, "Wrote data/metadata/AFRO_team_supervision_dictionary.xlsx")
} else log_msg(STEP, "WARNING: package 'writexl' not installed -- only the CSV dictionary was written")
log_msg(STEP, "Done.")
