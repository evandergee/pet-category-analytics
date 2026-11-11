# Pet-food category analytics (SQL Server + Power BI)

> Built by Evan Gilb, with Claude as an AI coding partner.

Consumer-packaged-goods category analytics on a **synthetic syndicated point-of-sale
(scanner) dataset** — the kind of weekly product × retailer data a CPG category
analyst works in (Nielsen / Circana style). SQL analytics layer + a Power BI
semantic model and report guide.

```powershell
.\run_analysis.ps1
```

Generate the data → build the analytics views → validate → guided tour → build the
Power BI views. Needs SQL Server (Express is fine) with the Chinook database (the
`cpg` and `pbi` schemas are created there) and `sqlcmd`. ~1 minute.

> **Synthetic data.** ~170 SKUs, 14 retailers, 156 weeks (2023–2025), ~200K fact rows.
> Purina brands + real competitor brands are used for realism only — no real sales data.

---

## The dataset (schema `cpg`)

| Table | Grain / contents |
|---|---|
| `cpg.Product` | ~170 SKUs — Purina (Pro Plan, Purina ONE, Beneful, Fancy Feast, Friskies, Tidy Cats, Dog/Cat Chow) + competitors (Blue Buffalo, Hill's, Royal Canin, Pedigree, Iams, Sheba…) + private label. Category, form, life stage, pack size, price tier |
| `cpg.Retailer` | Walmart, Chewy, Amazon, PetSmart, Petco, Target, Kroger, Costco… across Mass / Grocery / Club / Pet Specialty / E-Commerce / Farm & Ranch |
| `cpg.Calendar` | retail weeks (ending Saturday), 2023–2025 |
| `cpg.SalesFact` | **Product × Retailer × Week** — dollar / unit / volume(lb) sales, ACV distribution, **base vs incremental** dollars, feature / display / price-reduction flags, average selling price |

A story is built into the data: premium brands (Blue Buffalo, Pro Plan) gaining
share, Purina value brands and private label under pressure on price, a Purina line
launched mid-2024.

## Analytics layer (schema `cpg`, 9 views)

| View | Answers |
|---|---|
| `vCategoryMonthly` | category size, growth, base vs incremental $, price/lb — by month |
| `vBrandShare` | manufacturer & brand dollar / volume share, by month |
| `vShareTrend` | manufacturer share with **year-over-year share-point change** |
| `vDistributionVelocity` | ACV-weighted distribution, total distribution points (TDP), **velocity** ($ per point) |
| `vPricing` | price per lb by tier & brand, **gap to private label**, % volume on promo |
| `vPromotionEffectiveness` | promo weeks, incremental $, **lift %**, incremental $ per promo week, efficiency — by brand × retailer |
| `vChannelMix` | dollar share by channel, by month (e-commerce trend) |
| `vSkuProductivity` | **Pareto** — rank SKUs by $, cumulative %, delist candidates |
| `vGrowthDecomposition` | latest 52 weeks vs prior 52 — **$ growth split into distribution / velocity / price effects** |

## Sample output

*(one run — the generator is randomised)*

**Manufacturer share trend** — Purina is slowly ceding share to Blue Buffalo:

```
Year | Purina | Blue Buffalo | Private Label | Mars
2023 |  51.2% |         8.4% |          1.6% | 25.9%
2024 |  49.7% |        10.1% |          1.7% | 25.9%
2025 |  48.1% |        12.1% |          1.8% | 25.3%
```

**Growth decomposition** — Blue Buffalo's +$4.6M isn't discounting, it's distribution + velocity:

```
Brand         | $ Change | Distribution | Velocity | Price
Blue Buffalo  |   +4.56M |       +1.71M |   +2.90M |  -0.05M
Friskies      |   -1.49M |       -1.11M |   -0.54M |  +0.16M
Purina Pro Plan | +1.31M |       -0.10M |   +1.51M |  -0.10M
```

## Power BI layer (`powerbi/`)

| File | |
|---|---|
| `01_semantic_views.sql` | `pbi` schema — a clean star (`DimDate` / `DimProduct` / `DimRetailer` / `FactSales`) shaped for Import |
| `measures.dax` | ~35 measures — share, distribution & velocity, weekly YoY time intelligence, promo lift & efficiency, and a DAX version of the growth decomposition |
| `model-guide.md` | connect, relationships, mark-as-date-table, sort-by, formatting |
| `report-guide.md` | 4 pages visual-by-visual with wireframes: Category Overview · Brand & Share · Price & Promotion · Retailer & Channel |

## Skills demonstrated

- Syndicated / scanner data modelling — product × retailer × week, base vs incremental
- **Market share & share-shift** analysis, category management
- **Distribution (ACV / TDP) and velocity** decomposition
- **Trade-promotion effectiveness** — lift, efficiency, incremental ROI
- Price analysis — price per lb, premium gaps, promo depth
- A **growth "due-to" decomposition** (distribution / velocity / price) in both SQL and DAX
- Window functions, `PERCENTILE_CONT`, running totals, set-based synthetic data generation
- Power BI star-schema modelling + a DAX measure library + weekly time intelligence
- Automated data-quality validation (9 checks, all PASS)
