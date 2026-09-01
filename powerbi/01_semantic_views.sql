/* =============================================================================
   Power BI semantic layer  --  schema  pbi
   -----------------------------------------------------------------------------
   Import these four views into Power BI Desktop
   (Get Data -> SQL Server -> .\SQLEXPRESS / Chinook).  Star schema:

       pbi.DimDate      one row per retail week      (mark as the date table)
       pbi.DimProduct   one row per SKU
       pbi.DimRetailer  one row per retailer
       pbi.FactSales    ProductId x RetailerId x WeekKey

   Depends on the cpg.* objects from ..\sql\00.  Idempotent.
   Run:  ..\q.ps1 -File powerbi\01_semantic_views.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

IF SCHEMA_ID('pbi') IS NULL EXEC('CREATE SCHEMA pbi');
GO

/* ---------------------------------------------------------------- DimDate ---- */
CREATE OR ALTER VIEW pbi.DimDate AS
SELECT
    WeekKey        = WeekKey,
    WeekEndingDate = WeekEndingDate,
    [Year]         = [Year],
    [Quarter]      = CONCAT([Year], '-', [Quarter]),
    [Month]        = MonthName,
    MonthYear      = MonthYear,
    MonthYearSort  = MonthYearSort,
    WeekOfYear     = WeekOfYear,
    WeekLabel      = CONCAT('W', RIGHT('0' + CAST(WeekOfYear AS varchar(2)), 2), ' ', [Year]),
    IsHolidayWeek  = CONVERT(bit, IsHolidayWeek)
FROM cpg.Calendar;
GO

/* -------------------------------------------------------------- DimProduct --- */
CREATE OR ALTER VIEW pbi.DimProduct AS
SELECT
    p.ProductId,
    p.UPC,
    p.Manufacturer,
    ManufacturerGroup = CASE WHEN p.Manufacturer = 'Nestle Purina' THEN 'Nestle Purina'
                             WHEN p.Manufacturer = 'Private Label'  THEN 'Private Label'
                             ELSE 'Competitor' END,
    p.Brand,
    p.SubBrand,
    p.Category,
    p.Form,
    p.LifeStage,
    p.PriceTier,
    p.PackSizeLb,
    IsPurina    = CONVERT(bit, CASE WHEN p.Manufacturer = 'Nestle Purina' THEN 1 ELSE 0 END),
    LaunchWeek  = p.LaunchWeekKey
FROM cpg.Product p;
GO

/* ------------------------------------------------------------- DimRetailer --- */
CREATE OR ALTER VIEW pbi.DimRetailer AS
SELECT
    r.RetailerId,
    r.RetailerName,
    r.Channel,
    ChannelGroup = CASE WHEN r.Channel = 'E-Commerce' THEN 'E-Commerce' ELSE 'Brick & Mortar' END,
    r.ACVWeight
FROM cpg.Retailer r;
GO

/* -------------------------------------------------------------- FactSales ---- */
CREATE OR ALTER VIEW pbi.FactSales AS
SELECT
    f.ProductId,
    f.RetailerId,
    f.WeekKey,
    f.DollarSales,
    f.UnitSales,
    f.VolumeSalesLb,
    f.BaseDollars,
    f.IncrementalDollars,
    f.BaseUnits,
    IncrementalUnits  = f.UnitSales - f.BaseUnits,
    f.ACVDistribution,                                   -- sum across retailers = total distribution points
    f.AvgSellingPrice,
    f.BasePrice,
    AnyPromo          = CONVERT(bit, f.AnyPromo),
    FeatureFlag       = CONVERT(bit, f.FeatureFlag),
    DisplayFlag       = CONVERT(bit, f.DisplayFlag),
    PromoType         = CASE WHEN f.AnyPromo = 0 THEN 'No promo'
                             WHEN f.FeatureFlag = 1 AND f.DisplayFlag = 1 THEN 'Feature & Display'
                             WHEN f.FeatureFlag = 1 THEN 'Feature'
                             WHEN f.DisplayFlag = 1 THEN 'Display'
                             ELSE 'Price reduction only' END,
    PromoDollars      = CASE WHEN f.AnyPromo = 1 THEN f.DollarSales ELSE 0 END,
    PromoWeek         = CONVERT(tinyint, f.AnyPromo)
FROM cpg.SalesFact f;
GO

PRINT 'pbi semantic layer built (4 views).';
GO
