# Reading configuration files and the indicator registry ---------------------

read_config <- function(path) {
  yaml::read_yaml(path)
}

#' Read the indicator registry and check active entries are complete.
read_registry <- function(path = "config/indicators.yml") {
  reg <- yaml::read_yaml(path)$indicators
  ids <- purrr::map_chr(reg, "id")
  if (anyDuplicated(ids)) {
    stop("Duplicate indicator ids in ", path, ": ",
         paste(unique(ids[duplicated(ids)]), collapse = ", "), call. = FALSE)
  }
  names(reg) <- ids
  purrr::walk(reg[purrr::map_chr(reg, "status") == "active"], check_indicator_spec)
  reg
}

active_indicator_ids <- function(path = "config/indicators.yml", source = c("acs", "pums", "any")) {
  source <- match.arg(source)
  reg <- yaml::read_yaml(path)$indicators
  keep <- purrr::keep(reg, ~ identical(.x$status, "active") &&
                        (source == "any" || identical(.x$source, source)))
  purrr::map_chr(keep, "id")
}

get_indicator_spec <- function(registry, id) {
  spec <- registry[[id]]
  if (is.null(spec)) stop("Indicator '", id, "' is not in the registry.", call. = FALSE)
  spec
}

#' Stop with a plain-language message if a registry entry is incomplete.
check_indicator_spec <- function(spec) {
  if (identical(spec$source, "pums")) {
    need <- c("id", "name", "vital_condition", "universe", "legacy_vintage")
    missing <- setdiff(need, names(spec))
    if (length(missing)) stop("Indicator '", spec$id, "' is missing: ",
                              paste(missing, collapse = ", "), call. = FALSE)
    return(invisible(TRUE))
  }
  need <- c("id", "name", "vital_condition", "source", "surveys", "geographies",
            "universe", "groups", "measures")
  missing <- setdiff(need, names(spec))
  if (length(missing)) {
    stop("Indicator '", spec$id, "' is missing: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  if (!identical(spec$source, "acs")) {
    stop("Indicator '", spec$id, "': source must be 'acs' or 'pums'.", call. = FALSE)
  }
  comps <- unique(c(names(spec$components),
                    unlist(purrr::map(spec$groups, ~ names(.x$components)))))
  for (g in spec$groups) {
    gc <- names(g$components %||% spec$components)
    if (is.null(gc)) stop("Indicator '", spec$id, "', group '", g$group, "' has no components.", call. = FALSE)
  }
  for (m in spec$measures) {
    used <- switch(m$type,
      count   = m$component,
      value   = m$component,
      percent = c(m$numerator, m$denominator),
      stop("Indicator '", spec$id, "', measure '", m$id,
           "': type must be 'count', 'value' or 'percent'.", call. = FALSE))
    if (m$type == "value" && !isTRUE(m$unit %in% c("count", "percent", "dollars"))) {
      stop("Indicator '", spec$id, "', measure '", m$id,
           "': a 'value' measure needs unit count, percent or dollars.", call. = FALSE)
    }
    bad <- setdiff(used, comps)
    if (length(bad)) {
      stop("Indicator '", spec$id, "', measure '", m$id,
           "' uses unknown component(s): ", paste(bad, collapse = ", "), call. = FALSE)
    }
  }
  # Consistency checks must refer to components that are published directly.
  count_comps <- purrr::map_chr(purrr::keep(spec$measures, ~ .x$type %in% c("count", "value")),
                                "component")
  chk_comps <- c(
    unlist(purrr::map(spec$checks$parts_equal_total, ~ c(.x$parts, .x$total))),
    spec$checks$subgroups_sum_to_total$components,
    unlist(purrr::map(spec$checks$ordered, "components"))
  )
  # Percentages must publish their numerator and denominator, so readers (and
  # the numerator <= denominator check) can see the parts.
  pct_comps <- unlist(purrr::map(purrr::keep(spec$measures, ~ .x$type == "percent"),
                                 ~ c(.x$numerator, .x$denominator)))
  bad <- setdiff(pct_comps, count_comps)
  if (length(bad)) {
    stop("Indicator '", spec$id, "': percentage parts need a count measure too: ",
         paste(bad, collapse = ", "), call. = FALSE)
  }
  bad <- setdiff(chk_comps, count_comps)
  if (length(bad)) {
    stop("Indicator '", spec$id, "': checks use component(s) with no count measure: ",
         paste(bad, collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

#' Long table of every ACS variable an indicator needs.
indicator_variables <- function(spec) {
  purrr::map_dfr(spec$groups, function(g) {
    comps <- g$components %||% spec$components
    purrr::imap_dfr(comps, function(nums, comp) {
      nums <- unlist(nums)
      # A number like "003" refers to the group's table; a full ID like
      # "B23008_004" can pull a variable from another table.
      full <- grepl("^[BCS][0-9]{5}[A-Z]?_", nums)
      variable <- ifelse(full, nums, paste0(g$table, "_", nums))
      tibble::tibble(
        group = g$group,
        table = sub("_.*$", "", variable),
        component = comp,
        variable = variable
      )
    })
  })
}

`%||%` <- function(x, y) if (is.null(x)) y else x
