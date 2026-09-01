/* =============================================================================
   Guided tour -- pet-food category analytics
   Run:  .\q.ps1 -File sql\03_demo.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

PRINT '========== 1. Category size & growth -- $ (millions) by year x category ==========';
SELECT Category,
       [2023] = CAST(SUM(CASE WHEN [Year]=2023 THEN DollarSales END)/1e6 AS decimal(10,1)),
       [2024] = CAST(SUM(CASE WHEN [Year]=2024 THEN DollarSales END)/1e6 AS decimal(10,1)),
       [2025] = CAST(SUM(CASE WHEN [Year]=2025 THEN DollarSales END)/1e6 AS decimal(10,1)),
       YoY_25v24_Pct = CAST(100.0 * (SUM(CASE WHEN [Year]=2025 THEN DollarSales END)
                                    - SUM(CASE WHEN [Year]=2024 THEN DollarSales END))
                            / NULLIF(SUM(CASE WHEN [Year]=2024 THEN DollarSales END), 0) AS decimal(6,1))
FROM cpg.vCategoryMonthly GROUP BY Category ORDER BY [2025] DESC;

PRINT '========== 2. Manufacturer dollar share + year-over-year change (latest month) ==========';
SELECT Manufacturer, DollarShare, DollarShare_PY, SharePointChg_YoY
FROM cpg.vShareTrend
WHERE MonthYearSort = (SELECT MAX(MonthYearSort) FROM cpg.vShareTrend)
ORDER BY DollarShare DESC;

PRINT '========== 3. Share trend -- Purina vs Blue Buffalo vs Private Label, by year ==========';
SELECT c.[Year],
       Purina_Pct       = CAST(100.0*SUM(CASE WHEN p.Manufacturer='Nestle Purina'      THEN f.DollarSales END)/SUM(f.DollarSales) AS decimal(5,1)),
       BlueBuffalo_Pct  = CAST(100.0*SUM(CASE WHEN p.Manufacturer='General Mills'       THEN f.DollarSales END)/SUM(f.DollarSales) AS decimal(5,1)),
       PrivateLabel_Pct = CAST(100.0*SUM(CASE WHEN p.Manufacturer='Private Label'       THEN f.DollarSales END)/SUM(f.DollarSales) AS decimal(5,1)),
       Mars_Pct         = CAST(100.0*SUM(CASE WHEN p.Manufacturer='Mars Petcare'        THEN f.DollarSales END)/SUM(f.DollarSales) AS decimal(5,1))
FROM cpg.SalesFact f JOIN cpg.Product p ON p.ProductId=f.ProductId JOIN cpg.Calendar c ON c.WeekKey=f.WeekKey
GROUP BY c.[Year] ORDER BY c.[Year];

PRINT '========== 4. Distribution & velocity -- biggest TDP swings (latest month vs 12 mo ago) ==========';
;WITH dv AS (
    SELECT Brand, Manufacturer, MonthYearSort, AvgWeeklyTDP, DollarsPerTDP,
           TDP_PY = LAG(AvgWeeklyTDP, 12) OVER (PARTITION BY Brand ORDER BY MonthYearSort)
    FROM cpg.vDistributionVelocity
)
SELECT TOP 10 Brand, Manufacturer, AvgWeeklyTDP, TDP_Change_YoY = CAST(AvgWeeklyTDP - TDP_PY AS decimal(10,1)), DollarsPerTDP
FROM dv WHERE MonthYearSort = (SELECT MAX(MonthYearSort) FROM dv) AND TDP_PY IS NOT NULL
ORDER BY ABS(AvgWeeklyTDP - TDP_PY) DESC;

PRINT '========== 5. Pricing -- price per lb by tier, and Purina premium gap to private label ==========';
SELECT p.PriceTier,
       AvgPricePerLb = CAST(SUM(f.DollarSales)/SUM(f.VolumeSalesLb) AS decimal(7,2)),
       VolumeShare_Pct = CAST(100.0*SUM(f.VolumeSalesLb)/SUM(SUM(f.VolumeSalesLb)) OVER() AS decimal(5,1))
FROM cpg.SalesFact f JOIN cpg.Product p ON p.ProductId=f.ProductId
GROUP BY p.PriceTier
ORDER BY AvgPricePerLb;

SELECT Manufacturer,
       VolumeOnPromo_Pct = CAST(100.0*SUM(CASE WHEN f.AnyPromo=1 THEN f.VolumeSalesLb ELSE 0 END)/SUM(f.VolumeSalesLb) AS decimal(5,1))
FROM cpg.SalesFact f JOIN cpg.Product p ON p.ProductId=f.ProductId
GROUP BY Manufacturer ORDER BY VolumeOnPromo_Pct DESC;

PRINT '========== 6. Promotion effectiveness -- most & least efficient brand x retailer ==========';
SELECT TOP 8 Brand, RetailerName, Channel, PromoWeeks, Lift_Pct, IncrDollarsPerPromoWeek, Efficiency_IncrPerBaseDollar
FROM cpg.vPromotionEffectiveness WHERE PromoWeeks >= 20
ORDER BY Efficiency_IncrPerBaseDollar DESC;
SELECT TOP 5 Brand, RetailerName, Lift_Pct, Efficiency_IncrPerBaseDollar
FROM cpg.vPromotionEffectiveness WHERE PromoWeeks >= 20
ORDER BY Efficiency_IncrPerBaseDollar ASC;

PRINT '========== 7. Channel mix -- dollar share by channel, 2023 vs 2025 ==========';
SELECT Channel,
       [2023] = CAST(AVG(CASE WHEN [Year]=2023 THEN ChannelShare END) AS decimal(5,1)),
       [2025] = CAST(AVG(CASE WHEN [Year]=2025 THEN ChannelShare END) AS decimal(5,1))
FROM cpg.vChannelMix GROUP BY Channel ORDER BY [2025] DESC;

PRINT '========== 8. SKU productivity (Pareto) ==========';
SELECT TOP 10 DollarRank, Brand, SubBrand, Dollars, DollarShare, CumDollarShare FROM cpg.vSkuProductivity ORDER BY DollarRank;
SELECT SKUs = COUNT(*),
       SKUs_for_80pct = SUM(CASE WHEN CumDollarShare <= 80 THEN 1 ELSE 0 END),
       Tail_SKUs_to_review = SUM(CASE WHEN TailFlag <> '' THEN 1 ELSE 0 END)
FROM cpg.vSkuProductivity;

PRINT '========== 9. Growth decomposition -- where the last 52 weeks'' change came from ==========';
SELECT TOP 12 Brand, PriorDollars, CurrentDollars, DollarChange,
       DistributionEffect, VelocityEffect, PriceEffect
FROM cpg.vGrowthDecomposition
ORDER BY ABS(DollarChange) DESC;
GO
