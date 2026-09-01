# Power BI report — page-by-page build guide

Four pages. Put a shared slicer panel on the left of every page (sync the slicers
across pages: **View → Sync slicers**).

**Slicers (all pages):** `DimDate[MonthYear]` (as a between-slider on `WeekEndingDate`),
`DimProduct[Category]`, `DimProduct[Manufacturer]`, `DimRetailer[Channel]`.

---

## Page 1 — Category Overview

```
┌───────────┬──────────────────────────────────────────────────────────┐
│           │  [Dollar Sales] [Volume (lbs)] [Dollar Sales YoY %]       │  ← 5 KPI cards
│  slicers  │  [% Dollars on Promo] [Price per Lb]                      │
│           ├───────────────────────────────┬──────────────────────────┤
│           │  Line: Dollar Sales by        │  Bar: Dollar Sales by     │
│           │  DimDate[MonthYear]           │  DimProduct[Category]     │
│           │  + Dollar Sales PY (2nd line) │  (with YoY % as tooltip)  │
│           ├───────────────────────────────┴──────────────────────────┤
│           │  Bar: top 12 DimProduct[Brand] by Dollar Sales,          │
│           │  colour = ManufacturerGroup (Purina / Competitor / PL)   │
└───────────┴──────────────────────────────────────────────────────────┘
```

## Page 2 — Brand & Share

- **Donut / bar:** `Dollar Share %` by `DimProduct[Manufacturer]` (current period).
- **Line:** `Dollar Share %` by `MonthYear`, one line per Manufacturer — the share-trend chart. Add `Purina Dollar Share %` as a reference.
- **Ranked bar:** `Share Point Change YoY` by `Brand` (top gainers green, losers red) — sort ascending, show top and bottom 10.
- **Matrix:** rows `Manufacturer` › `Brand`, values `Dollar Sales`, `Dollar Share %`, `Share Point Change YoY`, `Volume Share %`.
- **Card:** `Purina Dollar Share %` big, with `Share Point Change YoY` underneath.

## Page 3 — Price & Promotion

- **Bar:** `Price per Lb` by `DimProduct[PriceTier]`, with `Volume Share %` as a secondary bar or label.
- **Bar:** `% Volume on Promo` by `Manufacturer` — sorted descending.
- **Column:** `Promo Lift %` by `FactSales[PromoType]`.
- **Scatter:** X = `Promo Lift %`, Y = `Promo Efficiency`, bubble size = `Incremental Dollars`, legend = `Manufacturer`, details = `Brand`. Filter to `Promo Weeks >= 20`. → the promo effectiveness quadrant.
- **Waterfall:** category = a small disconnected table {Distribution, Velocity, Price}, values = `[Distribution Effect]`, `[Velocity Effect]`, `[Price Effect]`; or just three cards + a bar. Title: "What drove the last 52 weeks — $ change decomposed". Slice by Brand.

## Page 4 — Retailer & Channel

- **Stacked area:** `Dollar Sales` by `MonthYear`, series = `DimRetailer[Channel]` — the channel-mix-over-time chart. Add a second visual with `ChannelShare` (100% stacked).
- **Ranked bar:** `Dollar Sales` by `RetailerName`, colour by `Channel`.
- **Matrix:** rows `Brand`, columns `Channel`, values `Dollar Share %` — where each brand over/under-indexes.
- **Bar + line:** `Avg Weekly TDP` (bar) and `Dollars per TDP` (line) by `Brand` — distribution vs velocity.
- **Card:** e-commerce `Dollar Share %` with `Share Point Change YoY`.

---

## The story the report should tell

1. Category up ~3%/yr, driven by cat food and premium tiers.
2. **Purina is slowly losing share** (~51% → ~48%) — **Blue Buffalo is the taker** (~8% → ~12%), plus a little to private label.
3. Blue Buffalo's gain decomposes into **both distribution and velocity** — it's not just discounting.
4. Purina's value brands (Dog Chow, Friskies) are the soft spot — losing distribution.
5. Promo efficiency varies 2–3× by brand × retailer; value brands at club/grocery are the most efficient.
6. E-commerce is ~27% of the category and holding; pet specialty is quietly gaining.

Screenshot each page and drop the PNGs in `powerbi/screenshots/` for the repo.
