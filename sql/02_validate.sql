/* =============================================================================
   Validate the generated syndicated dataset
   -----------------------------------------------------------------------------
   One result set: Check | Detail | Status. Every row should read PASS.
   Run:  .\q.ps1 -File sql\02_validate.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

;WITH
share_by_month AS (
    SELECT MonthYearSort, ShareSum = SUM(DollarShare)
    FROM cpg.vShareTrend GROUP BY MonthYearSort
),
decomp AS (
    SELECT Brand,
           Resid = ABS(DollarChange - (DistributionEffect + VelocityEffect + PriceEffect))
                   / NULLIF(ABS(DollarChange), 0)
    FROM cpg.vGrowthDecomposition
    WHERE ABS(DollarChange) > 50000
),
checks AS (
    SELECT 1 AS Seq,
        'DollarSales = UnitSales x AvgSellingPrice (within $1)' AS [Check],
        CONCAT((SELECT COUNT(*) FROM cpg.SalesFact
                WHERE ABS(DollarSales - UnitSales * AvgSellingPrice) > 1.0), ' rows off') AS Detail,
        CASE WHEN (SELECT COUNT(*) FROM cpg.SalesFact
                   WHERE ABS(DollarSales - UnitSales * AvgSellingPrice) > 1.0) = 0
             THEN 'PASS' ELSE '*** FAIL ***' END AS Status

    UNION ALL
    SELECT 2, 'BaseDollars = BaseUnits x BasePrice (within $1)',
        CONCAT((SELECT COUNT(*) FROM cpg.SalesFact WHERE ABS(BaseDollars - BaseUnits * BasePrice) > 1.0), ' rows off'),
        CASE WHEN (SELECT COUNT(*) FROM cpg.SalesFact WHERE ABS(BaseDollars - BaseUnits * BasePrice) > 1.0) = 0
             THEN 'PASS' ELSE '*** FAIL ***' END

    UNION ALL
    SELECT 3, 'IncrementalDollars = max(0, DollarSales - BaseDollars)',
        CONCAT((SELECT COUNT(*) FROM cpg.SalesFact
                WHERE ABS(IncrementalDollars -
                          CASE WHEN DollarSales - BaseDollars < 0 THEN 0 ELSE DollarSales - BaseDollars END) > 1.0), ' rows off'),
        CASE WHEN (SELECT COUNT(*) FROM cpg.SalesFact
                   WHERE ABS(IncrementalDollars -
                             CASE WHEN DollarSales - BaseDollars < 0 THEN 0 ELSE DollarSales - BaseDollars END) > 1.0) = 0
             THEN 'PASS' ELSE '*** FAIL ***' END

    UNION ALL
    SELECT 4, 'No orphan fact rows (product / retailer / week all resolve)',
        CONCAT((SELECT COUNT(*) FROM cpg.SalesFact f
                WHERE NOT EXISTS (SELECT 1 FROM cpg.Product p   WHERE p.ProductId  = f.ProductId)
                   OR NOT EXISTS (SELECT 1 FROM cpg.Retailer r  WHERE r.RetailerId = f.RetailerId)
                   OR NOT EXISTS (SELECT 1 FROM cpg.Calendar c  WHERE c.WeekKey    = f.WeekKey)), ' orphans'),
        CASE WHEN (SELECT COUNT(*) FROM cpg.SalesFact f
                   WHERE NOT EXISTS (SELECT 1 FROM cpg.Product p   WHERE p.ProductId  = f.ProductId)
                      OR NOT EXISTS (SELECT 1 FROM cpg.Retailer r  WHERE r.RetailerId = f.RetailerId)
                      OR NOT EXISTS (SELECT 1 FROM cpg.Calendar c  WHERE c.WeekKey    = f.WeekKey)) = 0
             THEN 'PASS' ELSE '*** FAIL ***' END

    UNION ALL
    SELECT 5, 'ACVDistribution in [0, 100]; UnitSales >= BaseUnits; flags only on promo',
        CONCAT((SELECT COUNT(*) FROM cpg.SalesFact
                WHERE ACVDistribution < 0 OR ACVDistribution > 100
                   OR UnitSales < BaseUnits
                   OR (AnyPromo = 0 AND (FeatureFlag = 1 OR DisplayFlag = 1 OR PriceReductionFlag = 1))), ' bad rows'),
        CASE WHEN (SELECT COUNT(*) FROM cpg.SalesFact
                   WHERE ACVDistribution < 0 OR ACVDistribution > 100
                      OR UnitSales < BaseUnits
                      OR (AnyPromo = 0 AND (FeatureFlag = 1 OR DisplayFlag = 1 OR PriceReductionFlag = 1))) = 0
             THEN 'PASS' ELSE '*** FAIL ***' END

    UNION ALL
    SELECT 6, 'No sales before a SKU''s launch week',
        CONCAT((SELECT COUNT(*) FROM cpg.SalesFact f
                JOIN cpg.Product p ON p.ProductId = f.ProductId
                WHERE p.LaunchWeekKey IS NOT NULL AND f.WeekKey < p.LaunchWeekKey), ' early rows'),
        CASE WHEN (SELECT COUNT(*) FROM cpg.SalesFact f
                   JOIN cpg.Product p ON p.ProductId = f.ProductId
                   WHERE p.LaunchWeekKey IS NOT NULL AND f.WeekKey < p.LaunchWeekKey) = 0
             THEN 'PASS' ELSE '*** FAIL ***' END

    UNION ALL
    SELECT 7, 'Manufacturer dollar shares sum to 100% every month',
        CONCAT((SELECT COUNT(*) FROM share_by_month WHERE ABS(ShareSum - 100) > 0.1), ' months off'),
        CASE WHEN (SELECT COUNT(*) FROM share_by_month WHERE ABS(ShareSum - 100) > 0.1) = 0
             THEN 'PASS' ELSE '*** FAIL ***' END

    UNION ALL
    SELECT 8, 'Growth decomposition effects reconcile to the dollar change (<2%)',
        CONCAT((SELECT COUNT(*) FROM decomp WHERE Resid > 0.02), ' brands off'),
        CASE WHEN (SELECT COUNT(*) FROM decomp WHERE Resid > 0.02) = 0
             THEN 'PASS' ELSE '*** FAIL ***' END

    UNION ALL
    SELECT 9, 'Category is realistic (Purina 40-55% share, 25-45% of $ sold on promo)',
        (SELECT CONCAT('Purina ', FORMAT(SUM(CASE WHEN Manufacturer='Nestle Purina' THEN DollarSales END)/SUM(DollarSales),'P1'),
                       ', promo $ ', FORMAT(SUM(CASE WHEN AnyPromo=1 THEN DollarSales END)/SUM(DollarSales),'P1'))
         FROM cpg.SalesFact f JOIN cpg.Product p ON p.ProductId = f.ProductId),
        (SELECT CASE WHEN SUM(CASE WHEN Manufacturer='Nestle Purina' THEN DollarSales END)/SUM(DollarSales) BETWEEN 0.40 AND 0.55
                      AND SUM(CASE WHEN AnyPromo=1 THEN DollarSales END)/SUM(DollarSales) BETWEEN 0.25 AND 0.45
                     THEN 'PASS' ELSE '*** FAIL ***' END
         FROM cpg.SalesFact f JOIN cpg.Product p ON p.ProductId = f.ProductId)
)
SELECT [Check], Detail, Status FROM checks ORDER BY Seq;
GO
