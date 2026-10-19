ns_a <- "http://schemas.openxmlformats.org/drawingml/2006/main"
ns_r <- "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
emu <- 914400
todo_color <- "C00000"
# Most common link color on the template's slide 1; the theme's hlink color is red
link_color <- "1155CC"

# ---- Reading the previous slide ----------------------------------------

shape_text <- function(sp) {
  paste(xml_text(xml_find_all(sp, ".//a:t")), collapse = "")
}

find_shapes <- function(slide_xml) {
  sps <- xml_find_all(slide_xml, "/p:sld/p:cSld/p:spTree/p:sp")
  txt <- purrr::map_chr(sps, shape_text)
  ph_type <- xml_attr(xml_find_first(sps, "./p:nvSpPr/p:nvPr/p:ph"), "type")
  area <- as.numeric(xml_attr(xml_find_first(sps, ".//a:xfrm/a:ext"), "cx")) *
    as.numeric(xml_attr(xml_find_first(sps, ".//a:xfrm/a:ext"), "cy"))
  pick <- \(i) if (length(i) == 0) NULL else sps[[i[1]]]
  list(
    title = pick(which(ph_type == "title")),
    sldnum = pick(which(ph_type == "sldNum")),
    footer = pick(grep("Internal Use Only", txt)),
    aws_heading = pick(grep("^Monthly AWS usage$", trimws(txt))),
    caption = pick(grep("Report:", txt)),
    credits = pick(grep("credits remaining", txt, ignore.case = TRUE)),
    main = pick(intersect(
      grep("Engineering Highlights", txt),
      order(area, decreasing = TRUE)
    ))
  )
}

# officer indexes slides by file name, which can differ from presentation order
presented_slide <- function(deck, position = 1) {
  target <- basename(deck$presentation$slide_data()$target[position])
  files <- basename(deck$slide$get_metadata()$name)
  deck$slide$get_slide(match(target, files))$get()
}

shape_location <- function(node) {
  off <- xml_find_first(node, ".//a:xfrm/a:off")
  ext <- xml_find_first(node, ".//a:xfrm/a:ext")
  list(
    left = as.numeric(xml_attr(off, "x")) / emu,
    top = as.numeric(xml_attr(off, "y")) / emu,
    width = as.numeric(xml_attr(ext, "cx")) / emu,
    height = as.numeric(xml_attr(ext, "cy")) / emu
  )
}

chart_location <- function(slide_xml) {
  pics <- xml_find_all(slide_xml, "/p:sld/p:cSld/p:spTree/p:pic")
  if (length(pics) == 0) {
    return(list(left = 9.316, top = 0.688, width = 3.511, height = 2.950))
  }
  locs <- purrr::map(pics, shape_location)
  locs[[which.max(purrr::map_dbl(locs, \(l) l$width * l$height))]]
}

third_monday <- function(date) {
  first <- floor_date(date, "month")
  first + days((8 - wday(first, week_start = 1)) %% 7) + weeks(2)
}

previous_report_range <- function(deck) {
  shapes <- find_shapes(presented_slide(deck))
  txt <- shape_text(shapes$title)
  end_txt <- stringr::str_match(
    sub("Sept", "Sep", txt),
    "-\\s*([A-Z][a-z]+\\.? \\d{1,2},? \\d{4})"
  )[, 2]
  if (is.na(end_txt)) {
    cli::cli_abort(
      "Could not find a date range in the slide 1 title: {.val {txt}}"
    )
  }
  prev_end <- mdy(end_txt)
  start <- prev_end + days(1)
  list(prev_end = prev_end, start = start, end = third_monday(start %m+% months(1)))
}

# ---- Inline markdown to DrawingML runs ---------------------------------

md_run <- function(
  text,
  bold = FALSE,
  url = NA_character_,
  color = NA_character_
) {
  tibble::tibble(text = text, bold = bold, url = url, color = color)
}

md_runs <- function(text, bold = FALSE) {
  pattern <- "\\*\\*(.+?)\\*\\*|\\[([^]]+)\\]\\(([^)\\s]+)\\)|\\{\\{(.+?)\\}\\}"
  out <- list()
  rest <- text
  while (nzchar(rest)) {
    loc <- stringr::str_locate(rest, pattern)
    if (is.na(loc[1])) {
      out <- c(out, list(md_run(rest, bold)))
      break
    }
    m <- stringr::str_match(rest, pattern)
    if (loc[1] > 1) {
      out <- c(out, list(md_run(substr(rest, 1, loc[1] - 1), bold)))
    }
    if (!is.na(m[2])) {
      out <- c(out, list(md_runs(m[2], bold = TRUE)))
    } else if (!is.na(m[3])) {
      url <- if (grepl("^https?://", m[4])) m[4] else NA_character_
      out <- c(out, list(md_run(m[3], bold, url = url)))
    } else {
      out <- c(out, list(md_run(m[5], TRUE, color = todo_color)))
    }
    rest <- substr(rest, loc[2] + 1, nchar(rest))
  }
  purrr::list_rbind(out)
}

visible_chars <- function(text) {
  nchar(gsub("\\[([^]]+)\\]\\([^)]+\\)|\\*\\*|\\{\\{|\\}\\}", "\\1", text))
}

xml_escape <- function(x) {
  x |>
    gsub(pattern = "&", replacement = "&amp;", fixed = TRUE) |>
    gsub(pattern = "<", replacement = "&lt;", fixed = TRUE) |>
    gsub(pattern = ">", replacement = "&gt;", fixed = TRUE) |>
    gsub(pattern = "\"", replacement = "&quot;", fixed = TRUE)
}

runs_xml <- function(runs, sz = NULL) {
  sz_attr <- if (is.null(sz)) "" else sprintf(' sz="%d"', as.integer(sz * 100))
  purrr::pmap_chr(runs, \(text, bold, url, color) {
    fill <- if (!is.na(url)) {
      sprintf('<a:solidFill><a:srgbClr val="%s"/></a:solidFill>', link_color)
    } else if (!is.na(color)) {
      sprintf(
        '<a:solidFill><a:srgbClr val="%s"/></a:solidFill>',
        sub("#", "", color)
      )
    } else {
      '<a:solidFill><a:schemeClr val="dk1"/></a:solidFill>'
    }
    # officer's process_links() turns URL-valued r:id attributes into relationships on save.
    # hlinkClr="tx" makes PowerPoint use the run color instead of the theme's hlink color.
    link <- if (is.na(url)) {
      ""
    } else {
      sprintf(
        paste0(
          '<a:hlinkClick r:id="%s"><a:extLst>',
          '<a:ext uri="{A12FA001-AC4F-418D-AE19-62706E023703}">',
          '<ahyp:hlinkClr xmlns:ahyp="http://schemas.microsoft.com/office/drawing/2018/hyperlinkcolor" val="tx"/>',
          '</a:ext></a:extLst></a:hlinkClick>'
        ),
        xml_escape(officer:::officer_url_encode(url))
      )
    }
    sprintf(
      '<a:r><a:rPr lang="en"%s%s%s>%s%s</a:rPr><a:t>%s</a:t></a:r>',
      if (bold) ' b="1"' else "",
      sz_attr,
      if (is.na(url)) "" else ' u="sng"',
      fill,
      link,
      xml_escape(text)
    )
  }) |>
    paste(collapse = "")
}

paragraph_xml <- function(type, runs, sz) {
  pts <- as.integer(sz * 100)
  spacing <- '<a:spcBef><a:spcPts val="0"/></a:spcBef><a:spcAft><a:spcPts val="0"/></a:spcAft>'
  ppr <- switch(
    type,
    heading = sprintf(
      '<a:pPr indent="0" lvl="0" marL="0" rtl="0" algn="l"><a:lnSpc><a:spcPct val="115000"/></a:lnSpc>%s<a:buNone/></a:pPr>',
      spacing
    ),
    bullet1 = sprintf(
      '<a:pPr indent="-317500" lvl="0" marL="457200" rtl="0" algn="l"><a:lnSpc><a:spcPct val="100000"/></a:lnSpc>%s<a:buClr><a:schemeClr val="dk1"/></a:buClr><a:buSzPts val="%d"/><a:buChar char="&#9679;"/></a:pPr>',
      spacing,
      pts
    ),
    bullet2 = sprintf(
      '<a:pPr indent="-317500" lvl="1" marL="914400" rtl="0" algn="l"><a:lnSpc><a:spcPct val="100000"/></a:lnSpc>%s<a:buClr><a:schemeClr val="dk1"/></a:buClr><a:buSzPts val="%d"/><a:buChar char="&#9675;"/></a:pPr>',
      spacing,
      pts
    ),
    blank = sprintf(
      '<a:pPr indent="0" lvl="0" marL="0" rtl="0" algn="l">%s<a:buNone/></a:pPr>',
      spacing
    )
  )
  body <- if (is.null(runs) || nrow(runs) == 0) "" else runs_xml(runs, sz)
  sprintf('<a:p>%s%s<a:endParaRPr sz="%d"/></a:p>', ppr, body, pts)
}

set_paragraphs <- function(sp, paras_xml) {
  tx <- xml_find_first(sp, ".//p:txBody")
  xml_remove(xml_find_all(tx, "./a:p"))
  doc <- read_xml(sprintf(
    '<a:txBody xmlns:a="%s" xmlns:r="%s">%s</a:txBody>',
    ns_a,
    ns_r,
    paste(paras_xml, collapse = "")
  ))
  for (p in xml_children(doc)) {
    xml_add_child(tx, p)
  }
  invisible(sp)
}

fit_font_size <- function(paragraphs, box, base = 14, min = 9) {
  usable_w <- box$width - 0.2
  usable_h <- box$height - 0.2
  for (sz in seq(base, min, by = -0.5)) {
    char_w <- sz * 0.5 / 72
    indent <- ifelse(
      paragraphs$type == "bullet1",
      0.5,
      ifelse(paragraphs$type == "bullet2", 1, 0)
    )
    cpl <- floor((usable_w - indent) / char_w)
    n_lines <- pmax(1, ceiling(visible_chars(paragraphs$text) / cpl))
    line_h <- sz * 1.2 / 72 * ifelse(paragraphs$type == "heading", 1.15, 1)
    if (sum(n_lines * line_h) <= usable_h) {
      return(sz)
    }
  }
  cli::cli_warn(
    "Main text may overflow its box even at {min}pt; trim content on the slide."
  )
  min
}

# ---- Building the new slide --------------------------------------------

add_report_slide <- function(
  deck,
  start,
  end,
  paragraphs,
  chart_path,
  caption,
  credits_text
) {
  src <- presented_slide(deck)
  shapes <- find_shapes(src)
  missing <- names(purrr::keep(shapes, is.null))
  if (length(missing)) {
    cli::cli_abort("Slide 1 is missing expected shapes: {.val {missing}}")
  }
  chart_loc <- chart_location(src)

  deck <- add_slide(deck, layout = "OBJECT", master = "RAY Masters: Content")
  dst <- deck$slide$get_slide(length(deck))$get()
  tree <- xml_find_first(dst, "//p:spTree")
  copied <- purrr::map(shapes, \(s) xml_add_child(tree, s))

  title_paras <- xml_find_all(copied$title, ".//a:p")
  date_runs <- xml_find_all(title_paras[[length(title_paras)]], "./a:r")
  date_t <- xml_find_first(date_runs[[1]], "./a:t")
  xml_text(date_t) <- format_range(start, end)
  xml_remove(date_runs[-1])

  credits_paras <- xml_find_all(copied$credits, ".//a:p")
  credits_para <- credits_paras[[1]]
  xml_remove(credits_paras[-1])
  credits_runs <- xml_find_all(credits_para, "./a:r")
  first_t <- xml_find_first(credits_runs[[1]], "./a:t")
  xml_text(first_t) <- credits_text[1]
  xml_remove(credits_runs[-1])
  second <- xml_add_sibling(credits_para, credits_para, .where = "after", .copy = TRUE)
  second_t <- xml_find_first(second, ".//a:t")
  xml_text(second_t) <- credits_text[2]
  credits_off <- xml_find_first(copied$credits, ".//a:xfrm/a:off")
  credits_ext <- xml_find_first(copied$credits, ".//a:xfrm/a:ext")
  caption_xfrm <- xml_find_first(copied$caption, ".//a:xfrm")
  xml_set_attr(credits_off, "x", xml_attr(xml_find_first(caption_xfrm, "./a:off"), "x"))
  xml_set_attr(credits_ext, "cx", "3400000")

  cap_sz <- caption_font_size(shapes$caption)
  set_paragraphs(copied$caption, paragraph_xml("blank", caption, cap_sz))

  main_box <- shape_location(shapes$main)
  sz <- fit_font_size(paragraphs, main_box)
  paras <- purrr::map2_chr(paragraphs$type, paragraphs$text, \(type, text) {
    paragraph_xml(type, if (nzchar(text)) md_runs(text) else NULL, sz)
  })
  set_paragraphs(copied$main, paras)

  ph_with(
    deck,
    external_img(chart_path),
    location = do.call(ph_location, c(chart_loc, newlabel = "AWS usage chart"))
  )
}

caption_font_size <- function(sp) {
  sz <- xml_attr(xml_find_all(sp, ".//a:rPr[@sz]"), "sz")
  if (length(sz)) as.numeric(sz[1]) / 100 else 14
}

build_report_deck <- function(
  deck,
  out_path,
  start,
  end,
  paragraphs,
  chart_path,
  caption,
  credits_text
) {
  deck <- add_report_slide(
    deck,
    start,
    end,
    paragraphs,
    chart_path,
    caption,
    credits_text
  )
  deck <- move_slide(deck, index = length(deck), to = 1)
  print(deck, target = out_path)
  invisible(out_path)
}
