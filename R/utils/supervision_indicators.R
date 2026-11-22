# ============================================================
# supervision_indicators.R  -- the indicators and categories of the team supervision form
# Author: Gorgui Ba Toure
#
# One row per indicator: id, label, source column in the ONA form, group (which team type is asked), the answers that
# count as "favourable" (yes) and the answers that count as a valid answer (the rest -- blank, "Not applicable",
# typing errors -- is NA and not counted). lower_is_better = TRUE where a 'yes' is bad news (false finger marking,
# over-tallying). Add a row here to add an indicator everywhere (processing, summaries, dictionary, QC).
# ============================================================
library(data.table)

YN <- "Yes|No"
SUP_INDICATORS <- rbindlist(list(
  # --- house-to-house team (asked only when Type_of_supervision = H2H_team_supervision)
  list("house_marked",        "House marked",                    "H2H_team/HseMark",         "H2H", "Yes", YN, FALSE),
  list("pen_marker",          "Pen marker used",                 "H2H_team/PenMarker",       "H2H", "Yes", YN, FALSE),
  list("tally_recorded",      "Tally sheet recorded",            "H2H_team/RecordTally",     "H2H", "Yes", YN, FALSE),
  list("know_vvm",            "Team knows VVM",                  "H2H_team/knowVVM",         "H2H", "Yes", YN, FALSE),
  list("in_assigned_area",    "Team in its assigned area",       "H2H_team/AreaW",           "H2H", "Yes", YN, FALSE),
  list("asks_afp",            "Asks about AFP",                  "H2H_team/Asking_AFP",      "H2H", "Yes", YN, FALSE),
  list("afp_pictorial",       "AFP pictorial guide available",   "H2H_team/AFP_Pictorial",   "H2H", "Yes", YN, FALSE),
  list("revisits_missed",     "Revisits missed children",        "H2H_team/Revisit",         "H2H", "Yes", YN, FALSE),
  list("uses_pluses",         "Uses pluses",                     "H2H_team/Pluses",          "H2H", "Yes", YN, FALSE),
  list("records_nc",          "Records non-compliance",          "H2H_team/NCRecord",        "H2H", "Yes", YN, FALSE),
  list("reminds_ri",          "Reminds parents about routine immunisation", "H2H_team/remindedri", "H2H", "Yes", YN, FALSE),
  list("mobility_ensured",    "Team mobility ensured",           "H2H_team/Mobility",        "H2H", "Yes", YN, FALSE),
  list("icepack_frozen",      "Ice pack frozen",                 "H2H_team/icepack_status",  "H2H", "frozen", "frozen|cold_watery|warm", FALSE),
  list("vvm_stage_1_2",       "Vial VVM at stage I or II",       "H2H_team/VVM1or2",         "H2H", "I|II", "I|II|III|IV|untagged", FALSE),
  list("evidence_ffm",        "Evidence of false finger marking","H2H_team/evidence_ffm",    "H2H", "Yes", YN, TRUE),
  list("evidence_overtally",  "Evidence of over-tallying",       "H2H_team/evidence_overtallying", "H2H", "Yes", YN, TRUE),
  # --- fixed post team (Type_of_supervision = FP_team_supervision)
  list("fp_team_dip",         "Fixed post: team has the DIP",    "FP_team/Team_DIP",         "FP", "Yes", YN, FALSE),
  list("fp_social_mob",       "Fixed post: social mobilisation done", "FP_team/Soc_Mob_done", "FP", "Yes", YN, FALSE),
  list("fp_tallying",         "Fixed post: tallying done",       "FP_team/FP_tallying_OPV",  "FP", "Yes", YN, FALSE),
  list("fp_team_complete",    "Fixed post: team complete",       "FP_team/FP_team_complete", "FP", "Yes", YN, FALSE),
  list("fp_safety_box",       "Fixed post: safety box adequate", "FP_team/safety_box",       "FP", "Adequate", "Adequate|Not_adquate|Not_available", FALSE),
  list("fp_needles",          "Fixed post: needles/syringes adequate", "FP_team/Needle_syringes", "FP", "Adequate", "Adequate|Not_adquate|Not_available", FALSE),
  list("fp_vaccine_carrier",  "Fixed post: vaccine carrier adequate", "FP_team/Vaccine_carrier", "FP", "Adequate", "Adequate|Not_adquate|Not_available", FALSE),
  list("fp_ice_packs",        "Fixed post: conditioned ice packs adequate", "FP_team/Conditioned_Ice_Pack", "FP", "Adequate", "Adequate|Not_adquate|Not_available", FALSE)
), use.names = FALSE)
setnames(SUP_INDICATORS, c("id", "label", "source", "group", "favourable", "valid", "lower_is_better"))

# Type_of_supervision (as written in the ONA form) -> readable label and short code
SUP_TYPES <- data.table(
  raw   = c("H2H_team_supervision", "H2H_Temporary_FP_supervision", "FP_team_supervision", "special_team_supervision"),
  label = c("House-to-house team", "House-to-house with temporary fixed post", "Fixed post team", "Special team"),
  code  = c("H2H", "H2H_TFP", "FP", "SPECIAL")
)

# Other source columns used (besides the indicators)
SUP_SOURCE_COLS <- c("_id", "_submission_time", "today", "states", "lgas", "wards", "Settlement", "Settlement_type",
                     "agency", "designation", "monitor_gender", "sup_level", "Type_of_supervision", "TeamCode",
                     "ipdstype", "antigen", "CampDay_Supervision", "_geolocation[1]", "_geolocation[2]",
                     "H2H_team/Children_sampled", "H2H_team/Sampled_NFM", "H2H_team/Number_of_AFP_reported")
