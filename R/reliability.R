# Reliability guardrails ------------------------------------------------------
#
# For every estimate: standard error SE = MOE / z (z = 1.645 at 90%),
# coefficient of variation CV = SE / estimate x 100, and a plain flag:
#   reliable          CV below `reliable_cv_max` (default 15%)
#   use_with_caution  CV from `reliable_cv_max` to `caution_cv_max` (15-30%)
#   suppress          CV above `caution_cv_max`, a zero estimate, an estimate
#                     Census did not publish, or a percentage whose base is
#                     smaller than `min_denominator`.

RELIABILITY_LEVELS <- c("reliable", "use_with_caution", "suppress")

moe_z <- function(moe_level = 90) stats::qnorm(1 - (1 - moe_level / 100) / 2)

#' Add se, cv, reliability_flag and reliability notes.
#' `base` is the denominator count for percentages (NA for counts).
add_reliability <- function(df, rel_cfg, moe_level = 90) {
  z <- if (moe_level == 90) 1.645 else moe_z(moe_level)
  if (!"base" %in% names(df)) df$base <- NA_real_
  df |>
    dplyr::mutate(
      se = moe / z,
      cv = dplyr::if_else(!is.na(estimate) & estimate > 0, se / estimate * 100, NA_real_),
      reliability_flag = classify_reliability(estimate, moe, cv, base, rel_cfg),
      reliability_note = reliability_note(estimate, moe, cv, base, rel_cfg)
    )
}

classify_reliability <- function(estimate, moe, cv, base, rel_cfg) {
  dplyr::case_when(
    is.na(estimate) ~ "suppress",
    !is.na(base) & base < rel_cfg$min_denominator ~ "suppress",
    estimate == 0 ~ "suppress",
    is.na(moe) ~ "reliable",               # no sampling error published
    cv < rel_cfg$reliable_cv_max ~ "reliable",
    cv <= rel_cfg$caution_cv_max ~ "use_with_caution",
    TRUE ~ "suppress"
  )
}

reliability_note <- function(estimate, moe, cv, base, rel_cfg) {
  dplyr::case_when(
    is.na(estimate) ~ "Not published by the Census Bureau (sample too small or data filtered).",
    !is.na(base) & base < rel_cfg$min_denominator ~
      paste0("Based on fewer than ", rel_cfg$min_denominator, " cases; too small to report."),
    estimate == 0 ~ "Estimate is zero, so its reliability cannot be measured.",
    is.na(moe) ~ "Census publishes no margin of error for this estimate (controlled or complete count).",
    cv < rel_cfg$reliable_cv_max ~ NA_character_,
    cv <= rel_cfg$caution_cv_max ~ sprintf("CV %.1f%%: use with caution.", cv),
    TRUE ~ sprintf("CV %.1f%%: too uncertain to report.", cv)
  )
}
