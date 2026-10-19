engineering_repos <- c(
  "NASA-Openscapes/earthdata-cloud-cookbook",
  "Openscapes/openscapes.cloud"
)
events_repo <- "NASA-Openscapes/workshop-planning"

issues_to_tibble <- function(items) {
  if (length(items) == 0) {
    return(tibble::tibble(
      repo = character(), number = integer(), title = character(),
      url = character(), state = character(), created = as.Date(character()),
      updated = as.Date(character()), closed = as.Date(character()),
      labels = list(), body = character()
    ))
  }
  as_day <- \(x) as.Date(substr(x %||% NA_character_, 1, 10))
  purrr::map(items, \(i) tibble::tibble(
    repo = sub("https://github.com/([^/]+/[^/]+)/.*", "\\1", i$html_url),
    number = i$number,
    title = i$title,
    url = i$html_url,
    state = i$state,
    created = as_day(i$created_at),
    updated = as_day(i$updated_at),
    closed = as_day(i$closed_at),
    labels = list(purrr::map_chr(i$labels, "name")),
    body = i$body %||% ""
  )) |>
    purrr::list_rbind()
}

search_issues <- function(query) {
  res <- gh::gh("/search/issues", q = query, per_page = 100, .limit = Inf)
  issues_to_tibble(res$items)
}

issue_activity <- function(issues, start, end) {
  issues |>
    mutate(
      activity = case_when(
        between(created, start, end) ~ "opened",
        !is.na(closed) & between(closed, start, end) ~ "closed",
        .default = "updated"
      )
    )
}

get_engineering_issues <- function(start, end, repos = engineering_repos) {
  range <- paste0(start, "..", end)
  purrr::map(repos, \(r) search_issues(
    glue::glue("repo:{r} is:issue updated:{range}")
  )) |>
    purrr::list_rbind() |>
    issue_activity(start, end) |>
    arrange(repo, desc(updated))
}

form_field <- function(body, field) {
  pattern <- paste0("(?s)### ", field, "\\s*\\n\\s*\\n(.*?)(\\n###|$)")
  val <- stringr::str_match(body, pattern)[, 2] |> trimws()
  ifelse(is.na(val) | val == "_No response_", NA_character_, val)
}

get_workshop_events <- function(start, end, repo = events_repo) {
  issues <- gh::gh(
    "/repos/{repo}/issues",
    repo = repo, labels = "workshop", state = "all",
    per_page = 100, .limit = Inf
  ) |>
    purrr::discard(\(i) !is.null(i$pull_request)) |>
    issues_to_tibble()

  title_date <- stringr::str_extract(issues$title, "\\d{4}-\\d{1,2}-\\d{1,2}")
  issues |>
    mutate(
      event_start = suppressWarnings(ymd(coalesce(
        form_field(body, "Workshop Start Date"), title_date
      ))),
      event_end = suppressWarnings(ymd(form_field(body, "Workshop End Date"))),
      participants = form_field(body, "Estimated Number of Participants"),
      event = title |>
        stringr::str_remove("^\\[[^]]*\\]:\\s*") |>
        stringr::str_remove("^\\d{4}-\\d{1,2}-\\d{1,2}\\s*")
    ) |>
    filter(between(event_start, start, end)) |>
    arrange(event_start)
}

get_planning_activity <- function(start, end, repo = events_repo,
                                  exclude = integer()) {
  search_issues(glue::glue("repo:{repo} is:issue updated:{start}..{end}")) |>
    filter(!number %in% exclude) |>
    issue_activity(start, end) |>
    arrange(desc(updated))
}
