# monthly-reporting

Generates the NASA Openscapes monthly reporting slide and inserts it as slide 1 of a local copy of `NASA-Openscapes_PMR_Slides.pptx`.
The slide copies the layout of the current first slide and is built with officer.

## Usage

```sh
quarto render report.qmd
```

This will:

1. Authenticate googledrive and googlesheets4 (as `gdrive_email`) and download the current deck to `template/`.
2. Read the date range from slide 1's title.
   The new report period starts the day after that range ends and ends on the third Monday of the following month (`third_monday(start + months(1))`).
3. Pull the content, build the slide, and write `output/NASA-Openscapes_PMR_Slides.pptx`.
4. Render `report.html`, a review page with the chart, the raw items pulled from each source, and a thumbnail of the new slide.

Upload the output deck to Drive yourself.
The original deck is never modified.

## Settings

Edit the plain R variables at the top of the `setup` chunk in `report.qmd`:

  | Variable             | Purpose                                                           |
  | -------------------- | ----------------------------------------------------------------- |
  | `gdrive_email`       | Google account used for googledrive and googlesheets4             |
  | `deck_drive_id`      | Drive id of the source deck                                       |
  | `download_deck`      | Set to `FALSE` to reuse the existing local copy in `template/`    |
  | `template`, `output` | Paths of the local source deck and the generated deck             |
  | `start`, `end`       | Report range as `"YYYY-MM-DD"`; leave `""` to derive from slide 1 |
  | `cluster`            | Hub name used for the cost query                                  |

## Slide content

  | Section                    | Source                                                                                                                                                          |
  | -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | Monthly AWS usage chart    | jupycost / Cost Explorer: monthly totals for the six full calendar months before the report end (line), and daily cost by category for the report period (bars) |
  | Chart caption              | Generated from the top three cost categories and their colors                                                                                                   |
  | Credits used and remaining | `jupycost::get_credits_used()` for last month and the estimated balance of active credits from `jupycost::get_credits_remaining()`                              |
  | Engineering Highlights     | Issues opened, updated, or closed in the period in `NASA-Openscapes/earthdata-cloud-cookbook` and `Openscapes/openscapes.cloud`                                 |
  | Events hosted & supported  | `workshop`-labelled issues in `NASA-Openscapes/workshop-planning` with a start date in the period, plus other issues active in that repo                        |
  | Mentor Calls               | "we discussed & developed" summaries from the mentor calls Google Doc; other dated meeting notes are listed as "Other meetings"                                 |

**Note:** This is handy for populating boilerplate and pulling in the issues and meetings, but will require significant rewording and curating.
In particular:

- Get other events/items from the Flywheel reporting slide
- Tag reporting items with the deliverable numbers.

## Requirements

- R packages: officer, xml2, dplyr, lubridate, ggplot2, patchwork, ggtext, purrr, rlang, gh, googledrive, googlesheets4, jupycost (`pak::pak("Openscapes/jupycost")`).
- `NASA_AWS_ACCESS_KEY_ID`, `NASA_AWS_SECRET_ACCESS_KEY`, and `NASA_GRAFANA_TOKEN` environment variables.
- A GitHub token available to the gh package.

## Code

- `R/aws.R`: cost query and chart
- `R/github.R`: engineering issues, workshop events, planning activity
- `R/mentor-calls.R`: mentor calls doc export and parsing
- `R/content.R`: turns the fetched data into slide paragraphs (inline Markdown: `**bold**`, `[text](url)`, `{{TODO}}`)
- `R/slide.R`: finds the shapes on slide 1, copies them to a new slide, fills in the content, and moves it to position 1
