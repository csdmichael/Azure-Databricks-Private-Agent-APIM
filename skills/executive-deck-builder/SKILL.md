---
name: executive-deck-builder
description: Builds a high-fidelity, executive-ready PowerPoint (.pptx) file from Databricks Genie query results. Use whenever the user asks for a deck, presentation, slides, a report, or a readout. Scales the deck to the question with native charts, tables, KPI tiles, shapes-based diagrams, bullet summaries, and speaker notes, branded with a Microsoft header band, and returns the file for download.
---

# Executive deck builder

Build a real `.pptx` file with `python-pptx` and return it for download. Never ask the
user to build the file. Never stop at a slide plan.

## 1. Gather data first

Run at least three complementary Genie queries before writing any code:

1. A categorical breakdown (for example revenue by region).
2. A time trend (for example revenue by month).
3. A composition or secondary dimension (for example revenue by product family).

Use only values the tools return. Never invent, estimate, or extrapolate. If a query
returns no rows, say so and ask one clarifying question instead of guessing.

## 2. Canvas and layout

- 16:9 widescreen: `prs.slide_width = Inches(13.333)`, `prs.slide_height = Inches(7.5)`.
- Use the blank layout `prs.slide_layouts[6]` and place every element explicitly. Do not
  rely on placeholder autofit.
- Content area sits inside a 0.6 in margin. Header band occupies the top 0.75 in and the
  footer the bottom 0.4 in.
- Never overlap shapes. Cap slide titles at 90 characters and bullets at 120 characters so
  text cannot overflow.
- Body text minimum 14 pt. Slide titles 28-32 pt bold.

## 3. Header, footer, branding

Every slide except the title slide carries:

- The Microsoft logo mark at top-left: four 0.12 in squares in a 2x2 grid with a 0.02 in
  gap. Top-left `#F25022`, top-right `#7FBA00`, bottom-left `#00A4EF`, bottom-right
  `#FFB900`.
- The word `Microsoft` to the right of the mark, Segoe UI, 12 pt, `#737373`.
- A 1 pt horizontal rule beneath the header in `#E5E5E5` spanning the content width.
- A footer with the deck title on the left and the slide number on the right, Segoe UI
  9 pt, `#737373`.

If the user supplies an official logo image, use that image instead of the drawn mark.
The drawn mark is an approximation for internal use; official brand artwork is required
for anything customer-facing.

## 4. Visual fidelity

Charts must be native PowerPoint chart objects created with `CategoryChartData` and
`add_chart`. Never insert images of charts.

| Purpose | Chart type |
|---|---|
| Trend over time | `XL_CHART_TYPE.LINE_MARKERS` |
| Comparison across categories | `XL_CHART_TYPE.COLUMN_CLUSTERED` |
| Share of total | `XL_CHART_TYPE.DOUGHNUT` |
| Two measures, different scales | `COLUMN_CLUSTERED` plus a secondary-axis line |

Every chart needs a title, both axis titles with units, data labels on, a legend only when
there is more than one series, and a `number_format` matching the unit:

- Counts: `#,##0`
- Millions USD: `$#,##0,,"M"`
- Rates and percentages: `0.0%`

Set series colors explicitly from this palette, in order:
`#0078D4`, `#50E6FF`, `#243A5E`, `#FFB900`, `#D83B01`, `#107C10`.

**Tables** use `add_table` with a `#243A5E` header row, white bold header text, 10-11 pt
body text, numerics right-aligned with thousands separators, and units in the header.
Maximum 12 rows and 6 columns; if the data is larger, show the top rows and add an
`Other` row so totals still reconcile.

**KPI tiles** are rounded rectangles: value 28-32 pt bold `#243A5E`, label 11 pt `#737373`,
each including the unit and the period.

**Diagrams** are built from real PowerPoint shapes and connectors. Do not emit Mermaid and
do not fake a diagram with text boxes alone.

## 5. Deck structure

Deck length follows the request and the data, not a fixed template. Ask yourself what the
question actually needs, then build that.

**Always include these four:**

1. **Title** - deck title, the question asked, the date, and the source
   `Azure Databricks Unity Catalog (private)`.
2. **Executive summary** - 3 to 5 bullets, each containing a specific number.
3. **Evidence** - at least one chart or table carrying the numbers behind the summary.
4. **Findings and recommendations** - each tied to a number from the data.

**Add these when the data or the request warrants it:**

| Slide | Include when |
|---|---|
| Key stats / KPI tiles | There are 4 or more headline metrics worth isolating |
| Trend chart | The data has a time dimension |
| Comparison chart | There is a categorical dimension worth ranking |
| Composition chart | Share of total is part of the story |
| Data table | The underlying rows matter or the audience will ask for them |
| Diagram | A process or relationship view aids understanding |
| Per-segment detail | The user named specific regions, fabs, or product families |

Honour explicit instructions about length. If the user asks for a short readout, produce
the four core slides. If they ask for a full review, expand using the table above. A
typical executive review lands around nine to twelve slides, but never pad a deck to reach
a number, and never drop evidence to hit one.

Slide titles are assertions carrying a number, for example
`APAC leads 2025 at $101.85M, 37.5% of total`, never bare labels like `Revenue`.

Add speaker notes to every slide explaining how each number was derived and naming the
source table.

## 6. Verify before returning

After saving, reopen the file and assert:

- The four core slides are present.
- Every slide you planned exists, and every chart slide contains a chart object and every
  table slide contains a table.
- No text frame overflows its shape.

Then state the filename and give a one-line summary of what the deck contains.
