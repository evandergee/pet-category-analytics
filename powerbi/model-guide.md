# Power BI model — build guide

Everything here is done once in **Power BI Desktop**. ~15 minutes.

## 1. Connect and load

1. Run `powerbi\01_semantic_views.sql` first (creates the `pbi` schema).
2. Power BI Desktop → **Get data → SQL Server**
   - Server: `.\SQLEXPRESS` · Database: `Chinook`
   - Data Connectivity mode: **Import**
3. In the Navigator, tick **pbi.DimDate**, **pbi.DimProduct**, **pbi.DimRetailer**, **pbi.FactSales** → **Load**
4. In each table's properties, shorten the names to `DimDate`, `DimProduct`, `DimRetailer`, `FactSales`.

## 2. Relationships (Model view)

| From | To | Cardinality | Cross-filter |
|---|---|---|---|
| `FactSales[ProductId]` | `DimProduct[ProductId]` | many-to-one | single |
| `FactSales[RetailerId]` | `DimRetailer[RetailerId]` | many-to-one | single |
| `FactSales[WeekKey]` | `DimDate[WeekKey]` | many-to-one | single |

All three **active**. Star schema — no dimension-to-dimension relationships.

## 3. Mark the date table

Select `DimDate` → **Table tools → Mark as date table** → date column: **`WeekEndingDate`**.
(The model is weekly, so year-over-year measures shift by **364 days = 52 weeks** to keep weekday alignment — that's already baked into `measures.dax`.)

## 4. Sort-by-column

| Column | Sort by |
|---|---|
| `DimDate[MonthYear]` | `DimDate[MonthYearSort]` |
| `DimDate[Month]` | (set to month number — add a `MonthNumber` column or sort by `MonthYearSort`) |
| `DimProduct[PriceTier]` | create a 1–5 order column, or leave alphabetical |

## 5. Hide from report view

Right-click → Hide: every `*Id` and `*Key` column, `DimDate[MonthYearSort]`, `FactSales[BasePrice]`, `FactSales[AvgSellingPrice]` (use the measures instead), `FactSales[PromoDollars]`, `FactSales[PromoWeek]`.

## 6. Measures

Home → **Enter data** → make a one-column table named **`_Measures`** → Load.
Paste each measure from **`measures.dax`** (Modeling → New measure). Delete the dummy column.
Then move every measure onto `_Measures` (select measure → Home → Home table).

Formatting to set:
- `Dollar Sales`, `Base Dollars`, `Incremental Dollars`, `Promo Dollars`, `*Effect` → Currency, 0 dp
- `Dollar Share %`, `Volume Share %`, `% Dollars on Promo`, `% Volume on Promo`, `*YoY %`, `Promo Lift %`, `Promo Efficiency` → Percentage, 1 dp
- `Share Point Change YoY` → Percentage 1 dp, or a custom `+0.0 "pts";-0.0 "pts"`
- `Price per Unit`, `Price per Lb` → Currency 2 dp

## 7. Model diagram

```
                 DimDate
                    │
   DimProduct ── FactSales ── DimRetailer
   (SKU, brand,   (weekly $ /   (retailer,
    tier, form)    units / lbs /  channel)
                   ACV / promo)
```
