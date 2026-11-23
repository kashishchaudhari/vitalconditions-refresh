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

active_indicator_ids <- function(path = "config/indicators.yml") {
  reg <- yaml::read_yaml(path)$indicators
  purrr::map_chr(purrr::keep(reg, ~ identical(.x$status, "active")), "id")
}

get_indicator_spec <- function(registry, id) {
  spec <- registry[[id]]
  if (is.null(spec)) stop("Indicator '", id, "' is not in the registry.", call. = FALSE)
  spec
}

#' Stop with a plain-language message if a registry entry is incomplete.
check_indicator_spec <- function(spec) {
  need <- c("id", "name", "vital_condition", "source", "surveys", "geographies",
            "universe", "groups", "components", "measures")
  missing <- setdiff(need, names(spec))
  if (length(missing)) {
    stop("Indicator '", spec$id, "' is missing: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  if (!identical(spec$source, "acs")) {
    stop("Indicator '", spec$id, "': only source 'acs' can be active so far.", call. = FALSE)
  }
  comps <- names(spec$components)
  for (m in spec$measures) {
    used <- switch(m$type,
      count   = m$component,
      percent = c(m$numerator, m$denominator),
      stop("Indicator '", spec$id, "', measure '", m$id,
           "': type must be 'count' or 'percent'.", call. = FALSE))
    bad <- setdiff(used, comps)
    if (length(bad)) {
      stop("Indicator '", spec$id, "', measure '", m$id,
           "' uses unknown component(s): ", paste(bad, collapse = ", "), call. = FALSE)
    }
  }
  # Consistency checks must refer to components that are published as counts.
  count_comps <- purrr::map_chr(purrr::keep(spec$measures, ~ .x$type == "count"), "component")
  chk_comps <- c(
    unlist(purrr::map(spec$checks$parts_equal_total, ~ c(.x$parts, .x$total))),
    spec$checks$subgroups_sum_to_total$components
  )
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
      tibble::tibble(
        group = g$group,
        table = g$table,
        component = comp,
        variable = paste0(g$table, "_", nums)
      )
    })
  })
}

`%||%` <- function(x, y) if (is.null(x)) y else x
