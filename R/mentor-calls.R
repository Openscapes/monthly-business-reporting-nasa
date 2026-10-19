mentor_doc_id <- "19t0BqOuLWpedfqP67tBd0klQX5YVXAmPW2AKbN8odIA"

download_mentor_doc <- function(id = mentor_doc_id) {
  path <- tempfile(fileext = ".md")
  googledrive::drive_download(
    googledrive::as_id(id),
    path = path, type = "text/markdown", overwrite = TRUE
  )
  readLines(path, warn = FALSE, encoding = "UTF-8")
}

unescape_md <- function(x) {
  gsub("\\\\([][\\\\`*_{}()#+.!<>|~=-])", "\\1", x)
}

parse_heading_date <- function(heading, ref_date) {
  txt <- heading |>
    gsub(pattern = "[*#]", replacement = "") |>
    sub(pattern = "\\bSept\\b", replacement = "Sep") |>
    trimws()
  md <- stringr::str_extract(txt, "[A-Z][a-z]+\\.? \\d{1,2}(, \\d{4})?")
  if (is.na(md)) {
    return(as.Date(NA))
  }
  if (!grepl("\\d{4}", md)) {
    d <- suppressWarnings(mdy(paste0(md, ", ", year(ref_date))))
    if (!is.na(d) && d < ref_date %m-% months(6)) d <- d %m+% years(1)
    return(d)
  }
  suppressWarnings(mdy(md))
}

parse_doc_sections <- function(lines, ref_date) {
  h1 <- grep("^# ", lines)
  ends <- c(h1[-1] - 1, length(lines))
  tibble::tibble(
    heading = lines[h1],
    date = purrr::map_vec(lines[h1], parse_heading_date, ref_date = ref_date),
    body = purrr::map2(h1 + 1, ends, \(a, b) lines[seq(a, b)])
  ) |>
    filter(!is.na(date))
}

extract_summary <- function(body) {
  i <- grep("we discussed (&|and) developed", body, ignore.case = TRUE)
  if (length(i) == 0) {
    return(tibble::tibble(level = integer(), text = character()))
  }
  rest <- body[-seq_len(i[1])]
  stop_at <- grep("^#", rest)
  if (length(stop_at)) rest <- rest[seq_len(stop_at[1] - 1)]
  items <- rest[grepl("^\\s*[*-] ", rest)]
  tibble::tibble(
    level = nchar(sub("[*-].*", "", items)) %/% 2 + 1L,
    text = items |> sub(pattern = "^\\s*[*-] ", replacement = "") |>
      unescape_md() |> trimws()
  )
}

first_line <- function(body) {
  txt <- trimws(body[nzchar(trimws(body))])
  if (length(txt)) unescape_md(txt[1]) else NA_character_
}

get_mentor_calls <- function(start, end, lines = download_mentor_doc()) {
  parse_doc_sections(lines, ref_date = start) |>
    filter(between(date, start, end)) |>
    mutate(
      summary = purrr::map(body, extract_summary),
      is_mentor_call = purrr::map_lgl(body, \(b) {
        any(grepl("we discussed (&|and) developed|^## \\**Roll call", b,
          ignore.case = TRUE
        ))
      }),
      title = purrr::map_chr(body, first_line)
    ) |>
    select(date, is_mentor_call, title, summary) |>
    arrange(date)
}
