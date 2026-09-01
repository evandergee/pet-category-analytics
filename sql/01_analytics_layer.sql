/* =============================================================================
   Analytics layer -- the questions a CPG category analyst answers
   -----------------------------------------------------------------------------
     cpg.vCategoryMonthly       $ / unit / volume sales + base/incremental, by month x category
     cpg.vBrandShare            manufacturer & brand dollar / volume share, by month
     cpg.vShareTrend            manufacturer share with year-over-year share-point change
     cpg.vDistributionVelocity  ACV-weighted distribution, TDP, and velocity ($/point), by brand x month
     cpg.vPricing               price per lb by tier & brand, gap to private label, % volume on promo
     cpg.vPromotionEffectiveness  promo weeks, incremental $, lift %, efficiency -- by brand x retailer
     cpg.vChannelMix            dollar share by channel, by month
     cpg.vSkuProductivity       Pareto -- rank SKUs by $, cumulative %, tail flag
     cpg.vGrowthDecomposition   latest 52 wks vs prior 52 -- growth split into distribution / velocity / price

   Idempotent.  Run:  .\q.ps1 -File sql\01_analytics_layer.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

/* ---- 1. Category performance by month ------------------------------------------ */
CREATE OR ALTER VIEW cpg.vCategoryMonthly AS
SELECT
    c.MonthYear, c.MonthYearSort, c.[Year],
    p.Category,
    DollarSales        = CAST(SUM(f.DollarSales)        AS decimal(16,2)),
    UnitSales          = SUM(CONVERT(bigint, f.UnitSales)),
    VolumeSalesLb      = CAST(SUM(f.VolumeSalesLb)      AS decimal(16,2)),
    BaseDollars        = CAST(SUM(f.BaseDollars)        AS decimal(16,2)),
    IncrementalDollars = CAST(SUM(f.IncrementalDollars) AS decimal(16,2)),
    PromoDollarPct     = CAST(100.0 * SUM(f.IncrementalDollars) / NULLIF(SUM(f.DollarSales), 0) AS decimal(5,1)),
    AvgPricePerLb      = CAST(SUM(f.DollarSales) / NULLIF(SUM(f.VolumeSalesLb), 0) AS decimal(7,2))
FROM cpg.SalesFact f
JOIN cpg.Product  p ON p.ProductId = f.ProductId
JOIN cpg.Calendar c ON c.WeekKey   = f.WeekKey
GROUP BY c.MonthYear, c.MonthYearSort, c.[Year], p.Category;
GO

/* ---- 2. Brand / manufacturer share by month --------------------------------- */
CREATE OR ALTER VIEW cpg.vBrandShare AS
WITH m AS (
    SELECT c.MonthYear, c.MonthYearSort, p.Manufacturer, p.Brand, p.Category,
           Dollars = SUM(f.DollarSales),
           Volume  = SUM(f.VolumeSalesLb)
    FROM cpg.SalesFact f
    JOIN cpg.Product  p ON p.ProductId = f.ProductId
    JOIN cpg.Calendar c ON c.WeekKey   = f.WeekKey
    GROUP BY c.MonthYear, c.MonthYearSort, p.Manufacturer, p.Brand, p.Category
)
SELECT
    MonthYear, MonthYearSort, Manufacturer, Brand, Category,
    Dollars       = CAST(Dollars AS decimal(16,2)),
    DollarShare   = CAST(100.0 * Dollars / SUM(Dollars) OVER (PARTITION BY MonthYearSort) AS decimal(5,2)),
    CategoryDollarShare = CAST(100.0 * Dollars / SUM(Dollars) OVER (PARTITION BY MonthYearSort, Category) AS decimal(5,2)),
    VolumeShare   = CAST(100.0 * Volume / SUM(Volume) OVER (PARTITION BY MonthYearSort) AS decimal(5,2))
FROM m;
GO

/* ---- 3. Manufacturer share trend + YoY share-point change ------------------- */
CREATE OR ALTER VIEW cpg.vShareTrend AS
WITH mfr AS (
    SELECT c.[Year], c.MonthNumber, c.MonthYear, c.MonthYearSort, p.Manufacturer,
           Dollars = SUM(f.DollarSales)
    FROM cpg.SalesFact f
    JOIN cpg.Product  p ON p.ProductId = f.ProductId
    JOIN cpg.Calendar c ON c.WeekKey   = f.WeekKey
    GROUP BY c.[Year], c.MonthNumber, c.MonthYear, c.MonthYearSort, p.Manufacturer
),
sh AS (
    SELECT *, Share = 100.0 * Dollars / SUM(Dollars) OVER (PARTITION BY MonthYearSort)
    FROM mfr
)
SELECT
    MonthYear, MonthYearSort, Manufacturer,
    DollarShare       = CAST(Share AS decimal(5,2)),
    DollarShare_PY    = CAST(LAG(Share, 12) OVER (PARTITION BY Manufacturer ORDER BY MonthYearSort) AS decimal(5,2)),
    SharePointChg_YoY = CAST(Share - LAG(Share, 12) OVER (PARTITION BY Manufacturer ORDER BY MonthYearSort) AS decimal(5,2))
FROM sh;
GO

/* ---- 4. Distribution & velocity by brand x month --------------------------- */
CREATE OR ALTER VIEW cpg.vDistributionVelocity AS
WITH wk AS (   -- weekly total distribution points per brand (sum of ACV across retailers)
    SELECT c.MonthYearSort, c.MonthYear, f.WeekKey, p.Brand, p.Manufacturer,
           TDP     = SUM(f.ACVDistribution),
           Dollars = SUM(f.DollarSales),
           Units   = SUM(CONVERT(bigint, f.UnitSales))
    FROM cpg.SalesFact f
    JOIN cpg.Product  p ON p.ProductId = f.ProductId
    JOIN cpg.Calendar c ON c.WeekKey   = f.WeekKey
    GROUP BY c.MonthYearSort, c.MonthYear, f.WeekKey, p.Brand, p.Manufacturer
)
SELECT
    MonthYear, MonthYearSort, Manufacturer, Brand,
    AvgWeeklyTDP     = CAST(AVG(TDP) AS decimal(10,1)),
    Dollars          = CAST(SUM(Dollars) AS decimal(16,2)),
    DollarsPerTDP    = CAST(SUM(Dollars) / NULLIF(SUM(TDP), 0) AS decimal(10,2)),   -- $ velocity per distribution point
    UnitsPerTDP      = CAST(1.0 * SUM(Units) / NULLIF(SUM(TDP), 0) AS decimal(10,3))
FROM wk
GROUP BY MonthYear, MonthYearSort, Manufacturer, Brand;
GO

/* ---- 5. Pricing -------------------------------------------------------------- */
CREATE OR ALTER VIEW cpg.vPricing AS
WITH pl AS (   -- private-label price per lb, by category x month (the value benchmark)
    SELECT c.MonthYearSort, p.Category,
           PL_PricePerLb = SUM(f.DollarSales) / NULLIF(SUM(f.VolumeSalesLb), 0)
    FROM cpg.SalesFact f
    JOIN cpg.Product  p ON p.ProductId = f.ProductId
    JOIN cpg.Calendar c ON c.WeekKey   = f.WeekKey
    WHERE p.Brand = 'Private Label'
    GROUP BY c.MonthYearSort, p.Category
)
SELECT
    c.MonthYear, c.MonthYearSort, p.Category, p.PriceTier, p.Manufacturer, p.Brand,
    PricePerLb      = CAST(SUM(f.DollarSales) / NULLIF(SUM(f.VolumeSalesLb), 0) AS decimal(7,2)),
    BasePricePerLb  = CAST(SUM(CONVERT(decimal(18,2), f.BasePrice) * f.UnitSales) / NULLIF(SUM(f.VolumeSalesLb), 0) AS decimal(7,2)),
    PriceGapToPL_Pct = CAST(100.0 * (SUM(f.DollarSales) / NULLIF(SUM(f.VolumeSalesLb), 0) - pl.PL_PricePerLb)
                            / NULLIF(pl.PL_PricePerLb, 0) AS decimal(7,1)),
    VolumeOnPromo_Pct = CAST(100.0 * SUM(CASE WHEN f.AnyPromo = 1 THEN f.VolumeSalesLb ELSE 0 END)
                             / NULLIF(SUM(f.VolumeSalesLb), 0) AS decimal(5,1))
FROM cpg.SalesFact f
JOIN cpg.Product  p ON p.ProductId = f.ProductId
JOIN cpg.Calendar c ON c.WeekKey   = f.WeekKey
LEFT JOIN pl ON pl.MonthYearSort = c.MonthYearSort AND pl.Category = p.Category
GROUP BY c.MonthYear, c.MonthYearSort, p.Category, p.PriceTier, p.Manufacturer, p.Brand, pl.PL_PricePerLb;
GO

/* ---- 6. Promotion effectiveness by brand x retailer ------------------------ */
CREATE OR ALTER VIEW cpg.vPromotionEffectiveness AS
SELECT
    p.Manufacturer, p.Brand, r.RetailerName, r.Channel,
    PromoWeeks          = SUM(CASE WHEN f.AnyPromo = 1 THEN 1 ELSE 0 END),
    NonPromoWeeks       = SUM(CASE WHEN f.AnyPromo = 0 THEN 1 ELSE 0 END),
    IncrementalDollars  = CAST(SUM(f.IncrementalDollars) AS decimal(16,2)),
    Lift_Pct            = CAST(100.0 * SUM(CASE WHEN f.AnyPromo = 1 THEN f.UnitSales - f.BaseUnits ELSE 0 END)
                               / NULLIF(SUM(CASE WHEN f.AnyPromo = 1 THEN f.BaseUnits ELSE 0 END), 0) AS decimal(6,1)),
    IncrDollarsPerPromoWeek = CAST(SUM(f.IncrementalDollars)
                                   / NULLIF(SUM(CASE WHEN f.AnyPromo = 1 THEN 1 ELSE 0 END), 0) AS decimal(12,2)),
    Efficiency_IncrPerBaseDollar = CAST(SUM(f.IncrementalDollars)
                                        / NULLIF(SUM(CASE WHEN f.AnyPromo = 1 THEN f.BaseDollars ELSE 0 END), 0) AS decimal(6,3))
FROM cpg.SalesFact f
JOIN cpg.Product  p ON p.ProductId  = f.ProductId
JOIN cpg.Retailer r ON r.RetailerId = f.RetailerId
GROUP BY p.Manufacturer, p.Brand, r.RetailerName, r.Channel;
GO

/* ---- 7. Channel mix by month ---------------------------------------------- */
CREATE OR ALTER VIEW cpg.vChannelMix AS
WITH m AS (
    SELECT c.MonthYear, c.MonthYearSort, c.[Year], r.Channel,
           Dollars = SUM(f.DollarSales)
    FROM cpg.SalesFact f
    JOIN cpg.Retailer r ON r.RetailerId = f.RetailerId
    JOIN cpg.Calendar c ON c.WeekKey    = f.WeekKey
    GROUP BY c.MonthYear, c.MonthYearSort, c.[Year], r.Channel
)
SELECT
    MonthYear, MonthYearSort, [Year], Channel,
    Dollars      = CAST(Dollars AS decimal(16,2)),
    ChannelShare = CAST(100.0 * Dollars / SUM(Dollars) OVER (PARTITION BY MonthYearSort) AS decimal(5,2))
FROM m;
GO

/* ---- 8. SKU productivity (Pareto) ---------------------------------------------- */
CREATE OR ALTER VIEW cpg.vSkuProductivity AS
WITH s AS (
    SELECT f.ProductId, p.Manufacturer, p.Brand, p.SubBrand, p.Category, p.PriceTier,
           Dollars = SUM(f.DollarSales),
           Units   = SUM(CONVERT(bigint, f.UnitSales))
    FROM cpg.SalesFact f
    JOIN cpg.Product p ON p.ProductId = f.ProductId
    GROUP BY f.ProductId, p.Manufacturer, p.Brand, p.SubBrand, p.Category, p.PriceTier
)
SELECT
    ProductId, Manufacturer, Brand, SubBrand, Category, PriceTier,
    Dollars      = CAST(Dollars AS decimal(16,2)),
    DollarRank   = ROW_NUMBER() OVER (ORDER BY Dollars DESC),
    DollarShare  = CAST(100.0 * Dollars / SUM(Dollars) OVER () AS decimal(6,3)),
    CumDollarShare = CAST(100.0 * SUM(Dollars) OVER (ORDER BY Dollars DESC ROWS UNBOUNDED PRECEDING)
                          / SUM(Dollars) OVER () AS decimal(6,2)),
    TailFlag = CASE WHEN 100.0 * Dollars / SUM(Dollars) OVER () < 0.15 THEN 'review / delist' ELSE '' END
FROM s;
GO

/* ---- 9. Growth decomposition: latest 52 weeks vs prior 52 ------------------------
   Sequential split of the dollar change for each brand into:
     Distribution effect  (change in total distribution points)
     Velocity effect      (change in units sold per distribution point)
     Price effect         (change in average unit price)
   ---------------------------------------------------------------------------------- */
CREATE OR ALTER VIEW cpg.vGrowthDecomposition AS
WITH span AS (SELECT MaxIdx = MAX(WeekIndex) FROM cpg.Calendar),
tagged AS (
    SELECT f.*, p.Brand, p.Manufacturer,
           Period = CASE WHEN c.WeekIndex >  s.MaxIdx - 52 THEN 'Current'
                         WHEN c.WeekIndex >  s.MaxIdx - 104 AND c.WeekIndex <= s.MaxIdx - 52 THEN 'Prior' END,
           c.WeekKey AS wk
    FROM cpg.SalesFact f
    JOIN cpg.Product  p ON p.ProductId = f.ProductId
    JOIN cpg.Calendar c ON c.WeekKey   = f.WeekKey
    CROSS JOIN span s
),
agg AS (
    SELECT Manufacturer, Brand, Period,
           Dollars = SUM(DollarSales),
           Units   = SUM(CONVERT(bigint, UnitSales)),
           TDP     = SUM(ACVDistribution) / 52.0,          -- avg weekly total distribution points
           Weeks   = COUNT(DISTINCT wk)
    FROM tagged WHERE Period IS NOT NULL
    GROUP BY Manufacturer, Brand, Period
),
w AS (
    SELECT Manufacturer, Brand,
        Dollars_P = MAX(CASE WHEN Period='Prior'   THEN Dollars END),
        Dollars_C = MAX(CASE WHEN Period='Current' THEN Dollars END),
        Units_P   = MAX(CASE WHEN Period='Prior'   THEN Units   END),
        Units_C   = MAX(CASE WHEN Period='Current' THEN Units   END),
        TDP_P     = MAX(CASE WHEN Period='Prior'   THEN TDP     END),
        TDP_C     = MAX(CASE WHEN Period='Current' THEN TDP     END)
    FROM agg GROUP BY Manufacturer, Brand
),
e AS (
    SELECT *,
        Vel_P   = 1.0 * Units_P / NULLIF(TDP_P, 0) / 52.0,      -- units per point per week
        Vel_C   = 1.0 * Units_C / NULLIF(TDP_C, 0) / 52.0,
        Price_P = 1.0 * Dollars_P / NULLIF(Units_P, 0),
        Price_C = 1.0 * Dollars_C / NULLIF(Units_C, 0)
    FROM w
)
SELECT
    Manufacturer, Brand,
    PriorDollars   = CAST(Dollars_P AS decimal(16,2)),
    CurrentDollars = CAST(Dollars_C AS decimal(16,2)),
    DollarChange   = CAST(Dollars_C - Dollars_P AS decimal(16,2)),
    DistributionEffect = CAST((TDP_C - TDP_P) * Vel_P * Price_P * 52 AS decimal(16,2)),
    VelocityEffect     = CAST(TDP_C * (Vel_C - Vel_P) * Price_P * 52 AS decimal(16,2)),
    PriceEffect        = CAST(TDP_C * Vel_C * (Price_C - Price_P) * 52 AS decimal(16,2))
FROM e;
GO

PRINT 'Analytics layer built (9 views).';
GO
