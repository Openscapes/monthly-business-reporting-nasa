repo_names <- c(
  "NASA-Openscapes/earthdata-cloud-cookbook" = "NASA Earthdata Cloud Cookbook",
  "Openscapes/openscapes.cloud" = "openscapes.cloud (JupyterHub docs)"
)

md_link <- function(text, url) {
  text <- gsub("[][*{}]", "", text)
  paste0("[", text, "](", url, ")")
}

join_dates <- function(dates) {
  paste(format_day(sort(dates)), collapse = ", ")
}

engineering_paragraphs <- function(eng) {
  by_repo <- eng |>
    mutate(item = paste(activity, md_link(title, url))) |>
    group_by(repo) |>
    summarise(items = paste(item, collapse = "; "))

  tibble::tibble(
    type = c("heading", rep("bullet1", nrow(by_repo) + 1), "blank"),
    text = c(
      "**Engineering Highlights**: {{TODO: theme, e.g. Cloud infrastructure, user support}}",
      paste0(
        "**",
        coalesce(repo_names[by_repo$repo], by_repo$repo),
        "**: ",
        by_repo$items
      ),
      "{{TODO: other engineering highlights (hub work with 2i2c, earthaccess, etc.)}}",
      ""
    )
  )
}

event_text <- function(events) {
  dates <- ifelse(
    is.na(events$event_end) | events$event_end == events$event_start,
    format_day(events$event_start),
    paste(format_day(events$event_start), "-", format_day(events$event_end))
  )
  participants <- ifelse(
    is.na(events$participants),
    "",
    paste0(", est. ", events$participants, " participants")
  )
  paste0(
    "**",
    gsub("[*]", "", events$event),
    ".** ",
    dates,
    participants,
    " (",
    md_link(paste0("#", events$number), events$url),
    ")"
  )
}

mentor_text <- function(calls) {
  mc <- filter(calls, is_mentor_call)
  if (nrow(mc) == 0) {
    return(
      "**Mentor Calls.** {{TODO: no mentor calls found in the doc for this range}}"
    )
  }
  items <- mc$summary |>
    purrr::list_rbind() |>
    filter(level == 1) |>
    pull(text)
  paste0(
    "**Mentor Calls. ",
    join_dates(mc$date),
    ".** ",
    paste(sub("[.;]\\s*$", "", items), collapse = "; "),
    if (length(items)) "." else ""
  )
}

other_meetings_text <- function(calls) {
  om <- filter(calls, !is_mentor_call)
  if (nrow(om) == 0) {
    return(character())
  }
  paste0(
    "**Other meetings:** ",
    paste0(om$title, " (", format_day(om$date), ")", collapse = "; ")
  )
}

planning_text <- function(planning) {
  if (nrow(planning) == 0) {
    return(character())
  }
  paste0(
    "**Planning:** ",
    paste0(
      md_link(planning$title, planning$url),
      " (",
      planning$activity,
      ")",
      collapse = "; "
    )
  )
}

events_paragraphs <- function(events, calls, planning) {
  bullets <- c(
    if (nrow(events)) event_text(events),
    mentor_text(calls),
    other_meetings_text(calls),
    planning_text(planning),
    "**Recurring Hackdays.** earthaccess (biweekly); Cookbook (biweekly)",
    "{{TODO: other events (webinars, hackdays, blog posts)}}"
  )
  tibble::tibble(
    type = c("heading", rep("bullet1", length(bullets))),
    text = c("**Events hosted & supported**", bullets)
  )
}

slide_paragraphs <- function(eng, events, calls, planning) {
  bind_rows(
    engineering_paragraphs(eng),
    events_paragraphs(events, calls, planning),
    tibble::tibble(
      type = "heading",
      text = "**Issues and Risks / opportunities:** {{TODO}}"
    )
  )
}

caption_runs <- function(key, report_url) {
  color_runs <- purrr::pmap(key, \(color_name, color, label, ...) {
    md_run(c(color_name, paste0(" is ", label, "; ")), color = c(color, NA))
  }) |>
    purrr::list_rbind()
  color_runs$text[nrow(color_runs)] <- sub(
    "; $",
    ". ",
    color_runs$text[nrow(color_runs)]
  )
  bind_rows(
    color_runs,
    md_run("Report: "),
    md_run(report_url, url = report_url)
  )
}
