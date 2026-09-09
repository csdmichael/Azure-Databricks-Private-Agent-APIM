# Business Case

Enterprise business case for the private Azure Databricks to executive PowerPoint solution.

| File | Format |
|---|---|
| `private-data-to-powerpoint-business-case-final.pdf` | 11-page PDF |
| `private-data-to-powerpoint-business-case-final.pptx` | Editable PowerPoint |

## Headline figures

Modelled on a business unit of **100 active users**.

| Metric | Value |
|---|---|
| Annual run-rate benefit | $892.5K |
| Year-one ROI | 243% |
| Estimated payback | 2.4 months |
| Net monthly benefit | $74.4K |
| Productive hours released monthly | 1,125 ($84.4K capacity value) |
| Employee time per deck | 5 hours down to 2 |

Net year-one benefit is $717.5K after the $175K implementation estimate.

## Assumptions

| Assumption | Pilot | Business unit | Enterprise |
|---|---|---|---|
| Active users | 25 | 100 | 300 |
| Decks per user per month | 4 | 5 | 5 |
| Hours saved per deck | 2.5 | 3.0 | 3.5 |
| Loaded labor cost | $75/hour | $75/hour | $75/hour |
| Productive usage factor | 70% | 75% | 80% |
| Monthly operating cost | $5,000 | $10,000 | $25,000 |
| One-time implementation | $60,000 | $175,000 | $350,000 |

Core formula: *users × deck volume × hours saved × loaded hourly cost × productive usage*.

Capacity value measures time redirected to higher-value work. It is not a headcount
reduction commitment. Recalibrate with pilot usage and time-study data before using these
numbers with a customer.

## Where these files are surfaced

The showcase page renders the metrics, the assumption table, and an inline PDF viewer on
its **Business case** tab: <https://caldova-databricks-showcase.azurewebsites.net>

The web app serves its own copy from
[../../ui/src/assets/business-case](../../ui/src/assets/business-case) so the PDF loads
same-origin with the correct content type. **If you update the files here, copy them there
as well and redeploy**, otherwise the site keeps serving the previous version.

Figures shown on the page are maintained in
[../../ui/src/app/showcase/showcase.page.ts](../../ui/src/app/showcase/showcase.page.ts)
(`businessMetrics`, `scenarios`, and `useCases`).
