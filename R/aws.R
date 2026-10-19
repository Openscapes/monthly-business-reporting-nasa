component_labels <- c(
  "compute" = "user compute",
  "core" = "fixed core costs",
  "home storage" = "home directory storage",
  "networking" = "networking",
  "object storage" = "S3 object storage",
  "other" = "other"
)

palette_names <- c(
  "#6889e9" = "Blue",
  "#c33d69" = "Red",
  "#2ea597" = "Green",
  "#8356cd" = "Purple",
  "#e07a41" = "Orange"
)

get_report_costs <- function(
  start,
  end,
  n_months = 6,
  cluster = "openscapeshub"
) {
  withr::local_envvar(
    AWS_ACCESS_KEY_ID = Sys.getenv("NASA_AWS_ACCESS_KEY_ID"),
    AWS_SECRET_ACCESS_KEY = Sys.getenv("NASA_AWS_SECRET_ACCESS_KEY"),
    GRAFANA_TOKEN = Sys.getenv("NASA_GRAFANA_TOKEN"),
    AWS_REGION = "us-east-1"
  )
  first_month <- floor_date(end, "month") %m-% months(n_months)

  # end_date is exclusive, so add a day to include `end`
  costs <- jupycost::get_daily_usage_costs(
    start_date = min(start, first_month),
    end_date = end + days(1),
    cost_type = "unblended",
    cluster = cluster
  )

  costs |>
    filter(id == "unblended", date < Sys.Date())
}

plot_report_costs <- function(
  costs,
  start,
  end,
  n_months = 6,
  legend = FALSE
) {
  in_range <- filter(costs, between(date, start, end))
  total <- sum(in_range$cost)
  through <- max(in_range$date)
  partial <- through < end

  daily_title <- glue::glue(
    "Daily cost by category, {format_range(start, end)}: ",
    "${scales::comma(round(total))}",
    if (partial) " (through {format_day(through)})" else ""
  )

  last_month <- floor_date(end, "month") %m-% months(1)
  totals <- costs |>
    mutate(month = floor_date(date, "month")) |>
    filter(between(month, last_month %m-% months(n_months - 1), last_month)) |>
    group_by(month) |>
    summarise(cost = sum(cost))

  monthly_title <- glue::glue(
    "Monthly AWS cost for the NASA Openscapes 2i2c Hub, ",
    "{format(min(totals$month), '%b')} - {format(max(totals$month), '%b %Y')}"
  )

  by_component <- in_range |>
    group_by(date, service_component) |>
    summarise(cost = sum(cost), .groups = "drop") |>
    mutate(
      service_component = forcats::fct_reorder(
        service_component,
        cost,
        .fun = sum
      )
    )

  total_plot <- ggplot(totals, aes(month, cost)) +
    geom_line() +
    geom_point(size = 1.5) +
    scale_x_date(date_breaks = "1 month", date_labels = "%b") +
    labs(title = monthly_title, x = NULL, y = "Monthly cost ($)")

  service_plot <- ggplot(
    by_component,
    aes(date, cost, fill = service_component)
  ) +
    geom_col() +
    scale_fill_discrete(
      type = aws_ce_palette(nlevels(by_component$service_component))
    ) +
    scale_x_date(
      breaks = c(start, start + as.numeric(end - start) %/% 2, end),
      limits = c(start - 0.5, end + 0.5),
      labels = format_day,
      expand = expansion(mult = 0.01)
    ) +
    labs(title = daily_title, x = NULL, y = "Daily cost ($)") +
    if (!legend) guides(fill = "none")

  plot <- (total_plot / service_plot) &
    theme_classic(base_size = 13) &
    theme(plot.title = ggtext::element_textbox_simple(size = 12))

  attr(plot, "color_key") <- color_key(by_component)
  attr(plot, "total") <- total
  plot
}

color_key <- function(by_component, n = 3) {
  lvls <- levels(by_component$service_component)
  cols <- set_names(aws_ce_palette(length(lvls)), lvls)
  top <- rev(lvls)[seq_len(min(n, length(lvls)))]
  tibble::tibble(
    component = top,
    label = unname(dplyr::coalesce(component_labels[top], top)),
    color = unname(cols[top]),
    color_name = unname(palette_names[cols[top]])
  )
}

get_credits_text <- function() {
  withr::local_envvar(
    AWS_ACCESS_KEY_ID = Sys.getenv("NASA_AWS_ACCESS_KEY_ID"),
    AWS_SECRET_ACCESS_KEY = Sys.getenv("NASA_AWS_SECRET_ACCESS_KEY"),
    AWS_REGION = "us-east-1"
  )
  active <- jupycost::get_credits_remaining() |>
    filter(is.na(exhaust_date), end_date > Sys.time())
  last_month <- floor_date(Sys.Date(), "month") %m-% months(1)
  used <- jupycost::get_credits_used(
    end_date = floor_date(Sys.Date(), "month")
  ) |>
    filter(month == last_month)
  c(
    paste0(
      "$",
      format_k(used$credits_used),
      " credits used in ",
      format(last_month, "%B")
    ),
    paste0("$", format_k(sum(active$estimated_amount)), " credits remaining")
  )
}

format_k <- function(x) paste0(round(x / 1000, 1), "K")

save_usage_plot <- function(
  plot,
  path,
  loc = list(width = 3.5, height = 2.95)
) {
  ggsave(
    path,
    plot,
    width = loc$width * 2,
    height = loc$height * 2,
    dpi = 220,
    bg = "white"
  )
  path
}

format_day <- function(d, fmt = "%b %d") {
  sub(" 0", " ", format(d, fmt))
}

format_range <- function(start, end) {
  paste(format_day(start), "-", format_day(end, "%b %d %Y"))
}
