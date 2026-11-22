# ============================================================
# 02_process_supervision.R   (step 2 of run_pipeline.r)
# Author: Gorgui Ba Toure
#
# Reads the raw ONA download of each enabled form in config/forms.csv (data/raw/<iso3>_<form_id>.parquet) and writes
# ONE clean, visit-level table:  data/processed/supervision_clean.csv   (one row per supervision visit)
#
# What it does (nothing is changed in the raw files):
#   - keeps the useful columns, with standard names (state_raw / lga_raw are cleaned to standard names in step 3)
#   - removes repeated submissions of the same record (_id), keeping the latest
#   - visit date: the date typed in the form ('today') when it is plausible (not before the form's min_date, not
#     after the submission date + 1 day, not more than 60 days before it); otherwise the submission date
#     (date_source tells which). Records still outside min_date..today are left out and counted.
#   - indicators: 1 = favourable answer, 0 = other valid answer, NA = blank / not applicable / typing error
#     (see R/utils/supervision_indicators.R). Only the questions of that team type are filled.
#   - numbers typed in the form (children sampled, ...) outside a plausible range become NA
#   - GPS: lat/lon from the form; gps_valid = TRUE when both are within range and not 0/0
# Writes reports/process_summary.json (counts of everything above).
# ============================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
source("R/utils/env_loader.R"); source("R/utils/helpers.R"); source("R/utils/supervision_indicators.R")
STEP <- "02_process_supervision"
dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
dir.create("reports", showWarnings = FALSE, recursive = TRUE)

MAX_FUTURE_DAYS <- 1     # visit date may be at most this many days after the submission date
MAX_PAST_DAYS   <- 60    # ... and at most this many days before it
MAX_CHILDREN_SAMPLED <- 500; MAX_NFM <- 500; MAX_AFP <- 50

forms <- read_forms_config()
summ <- list(); out <- list()

for (i in seq_len(nrow(forms))) {
  f <- forms[i]
  path <- file.path("data/raw", sprintf("%s_%s.parquet", f$iso3, f$form_id))
  if (!file.exists(path)) { log_msg(STEP, "WARNING: ", path, " not found -- run the fetch step. Skipped."); next }
  log_msg(STEP, "Reading ", path)
  dt <- read_raw_columns(path, c(SUP_SOURCE_COLS, SUP_INDICATORS$source))
  n_raw <- nrow(dt)

  # --- repeated submissions
  dt[, record_id := `_id`]
  setorder(dt, `_submission_time`)
  dt <- dt[!duplicated(record_id, fromLast = TRUE) | is.na(record_id)]
  n_dup <- n_raw - nrow(dt)

  # --- visit date
  min_date <- as.Date(f$min_date)
  sub_date <- to_date(dt[["_submission_time"]])
  form_date <- to_date(dt[["today"]])
  plausible <- !is.na(form_date) & form_date >= min_date &
    form_date <= sub_date + MAX_FUTURE_DAYS & form_date >= sub_date - MAX_PAST_DAYS
  plausible[is.na(plausible)] <- FALSE
  dt[, visit_date := fifelse(plausible, form_date, sub_date)]
  dt[, date_source := fifelse(plausible, "form", "submission_time")]
  in_window <- !is.na(dt$visit_date) & dt$visit_date >= min_date & dt$visit_date <= Sys.Date() + 1
  n_out <- sum(!in_window)
  n_fallback <- sum(in_window & dt$date_source == "submission_time")
  dt <- dt[in_window]

  # --- place and team description
  res <- dt[, .(
    country = f$country, iso3 = f$iso3, form_id = f$form_id, record_id = record_id,
    submission_time = `_submission_time`, visit_date = visit_date, date_source = date_source,
    year = as.integer(format(visit_date, "%Y")), month = format(visit_date, "%Y-%m"),
    epi_week = sprintf("%s-W%02d", format(visit_date, "%G"), as.integer(format(visit_date, "%V"))),
    state_raw = clean_text(states), lga_raw = clean_text(lgas), ward = clean_text(wards),
    settlement = clean_text(Settlement), settlement_type = clean_text(Settlement_type),
    agency = clean_text(agency), supervisor_designation = clean_text(designation),
    supervisor_gender = clean_text(monitor_gender), sup_level = clean_text(sup_level),
    team_code = clean_text(TeamCode), campaign_type = clean_text(ipdstype), antigen = clean_text(antigen),
    camp_day = clean_text(CampDay_Supervision), type_raw = Type_of_supervision
  )]
  res[SUP_TYPES, on = .(type_raw = raw), `:=`(supervision_type = i.label, team_type = i.code)]
  res[is.na(supervision_type), `:=`(supervision_type = "Other / unknown", team_type = "OTHER")]
  res[, type_raw := NULL]

  # --- GPS
  lat <- to_num(dt[["_geolocation[1]"]]); lon <- to_num(dt[["_geolocation[2]"]])
  res[, `:=`(lat = lat, lon = lon,
             gps_valid = !is.na(lat) & !is.na(lon) & abs(lat) <= 90 & abs(lon) <= 180 & !(lat == 0 & lon == 0))]
  res[gps_valid == FALSE, `:=`(lat = NA_real_, lon = NA_real_)]

  # --- indicators (1 / 0 / NA)
  for (k in seq_len(nrow(SUP_INDICATORS))) {
    ind <- SUP_INDICATORS[k]
    v <- trimws(dt[[ind$source]])
    valid <- grepl(paste0("^(", ind$valid, ")$"), v)
    fav <- grepl(paste0("^(", ind$favourable, ")$"), v)
    set(res, j = paste0("ind_", ind$id), value = fifelse(valid, as.integer(fav), NA_integer_))
  }

  # --- numbers typed in the form
  cs <- to_num(dt[["H2H_team/Children_sampled"]]); nf <- to_num(dt[["H2H_team/Sampled_NFM"]])
  afp <- to_num(dt[["H2H_team/Number_of_AFP_reported"]])
  bad_cs <- !is.na(cs) & (cs < 0 | cs > MAX_CHILDREN_SAMPLED)
  bad_nf <- !is.na(nf) & (nf < 0 | nf > MAX_NFM | (!is.na(cs) & nf > cs))
  bad_afp <- !is.na(afp) & (afp < 0 | afp > MAX_AFP)
  res[, `:=`(children_sampled = fifelse(bad_cs, NA_real_, cs),
             not_fully_marked_sampled = fifelse(bad_nf | bad_cs, NA_real_, nf),
             afp_cases_reported = fifelse(bad_afp, NA_real_, afp))]
  res[, flag_number_outlier := bad_cs | bad_nf | bad_afp]

  out[[length(out) + 1]] <- res
  summ[[f$iso3]] <- list(country = f$country, form_id = f$form_id, records_downloaded = n_raw,
                         repeated_submissions_removed = n_dup, date_outside_window_removed = n_out,
                         date_from_submission_time = n_fallback, records_kept = nrow(res),
                         first_visit = as.character(min(res$visit_date)), last_visit = as.character(max(res$visit_date)),
                         number_outliers_set_to_NA = sum(res$flag_number_outlier))
  log_msg(STEP, sprintf("%s: %s downloaded, %s repeated removed, %s outside %s..today removed, %s kept (%s dated by submission time)",
                        f$country, format(n_raw, big.mark = ","), format(n_dup, big.mark = ","), format(n_out, big.mark = ","),
                        f$min_date, format(nrow(res), big.mark = ","), format(n_fallback, big.mark = ",")))
}

if (length(out) == 0) { log_msg(STEP, "FAILED: no raw data found -- nothing to process."); quit(status = 1) }
all <- rbindlist(out, use.names = TRUE, fill = TRUE)
fwrite(all, "data/processed/supervision_clean.csv", na = "")
write_json(list(timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), forms = summ), "reports/process_summary.json",
           auto_unbox = TRUE, pretty = TRUE)
log_msg(STEP, "Wrote data/processed/supervision_clean.csv (", format(nrow(all), big.mark = ","), " rows)")
