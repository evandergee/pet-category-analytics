/* =============================================================================
   Pet-food category analytics -- synthetic syndicated POS (scanner) data
   -----------------------------------------------------------------------------
   Builds a `cpg` schema that looks like a Nielsen / Circana syndicated dataset:
   weekly point-of-sale by product x retailer, with distribution, base vs
   incremental volume, and promotion flags.

       cpg.Retailer        14 retailers across 6 channels
       cpg.Calendar        ~156 retail weeks (week ending Saturday), 2023-2025
       cpg.Product         ~180 SKUs -- Purina brands + competitors + private label
       cpg.ProductPlan     synthetic-data driver ONLY (base price / velocity / trend)
       cpg.Distribution    which retailer carries which SKU + its ACV level
       cpg.SalesFact       Product x Retailer x Week  (the syndicated fact)

   Story baked into the data: premium brands (Blue Buffalo, Pro Plan) gaining
   share, value/private-label growing on price, e-commerce taking channel share,
   a Purina line launched mid-2024.

   Set-based, idempotent.  Run:  .\q.ps1 -File sql\00_generate_category.sql   (~1-2 min)
   ============================================================================= */
SET NOCOUNT ON;
GO

IF SCHEMA_ID('cpg') IS NULL EXEC('CREATE SCHEMA cpg');
GO

DROP TABLE IF EXISTS cpg.SalesFact;
DROP TABLE IF EXISTS cpg.Distribution;
DROP TABLE IF EXISTS cpg.ProductPlan;
DROP TABLE IF EXISTS cpg.Product;
DROP TABLE IF EXISTS cpg.Calendar;
DROP TABLE IF EXISTS cpg.Retailer;
GO

/* ============================ cpg.Retailer ================================== */
CREATE TABLE cpg.Retailer (
    RetailerId   int          NOT NULL CONSTRAINT PK_cpg_Retailer PRIMARY KEY,
    RetailerName varchar(20)  NOT NULL,
    Channel      varchar(16)  NOT NULL,
    ACVWeight    decimal(5,2) NOT NULL     -- share of category all-commodity volume, sums to 100
);
INSERT cpg.Retailer VALUES
 ( 1,'Walmart',       'Mass',          24.0),
 ( 2,'Chewy',         'E-Commerce',    14.0),
 ( 3,'Amazon',        'E-Commerce',     9.0),
 ( 4,'PetSmart',      'Pet Specialty', 11.0),
 ( 5,'Petco',         'Pet Specialty',  8.0),
 ( 6,'Target',        'Mass',           6.0),
 ( 7,'Kroger',        'Grocery',        6.0),
 ( 8,'Costco',        'Club',           5.0),
 ( 9,'Sam''s Club',   'Club',           3.0),
 (10,'Publix',        'Grocery',        3.0),
 (11,'Albertsons',    'Grocery',        3.0),
 (12,'Meijer',        'Grocery',        2.0),
 (13,'H-E-B',         'Grocery',        2.0),
 (14,'Tractor Supply','Farm & Ranch',   4.0);
GO

/* ============================ cpg.Calendar ================================= */
CREATE TABLE cpg.Calendar (
    WeekKey         int         NOT NULL CONSTRAINT PK_cpg_Calendar PRIMARY KEY,  -- yyyymmdd of week-ending Saturday
    WeekEndingDate  date        NOT NULL,
    WeekIndex       int         NOT NULL,   -- 1..N
    [Year]          int         NOT NULL,
    [Quarter]       varchar(2)  NOT NULL,
    MonthNumber     int         NOT NULL,
    MonthName       varchar(3)  NOT NULL,
    MonthYear       varchar(8)  NOT NULL,
    MonthYearSort   int         NOT NULL,
    WeekOfYear      int         NOT NULL,
    IsHolidayWeek   bit         NOT NULL
);
;WITH wk AS (
    /* first week-ending Saturday on/after 2023-01-07 */
    SELECT DATEADD(WEEK, value, CAST('2023-01-07' AS date)) AS wend
    FROM GENERATE_SERIES(0, DATEDIFF(WEEK, '2023-01-07', '2025-12-27'))
)
INSERT cpg.Calendar (WeekKey, WeekEndingDate, WeekIndex, [Year], [Quarter], MonthNumber,
                     MonthName, MonthYear, MonthYearSort, WeekOfYear, IsHolidayWeek)
SELECT
    YEAR(wend) * 10000 + MONTH(wend) * 100 + DAY(wend),
    wend,
    ROW_NUMBER() OVER (ORDER BY wend),
    YEAR(wend),
    CONCAT('Q', DATEPART(QUARTER, wend)),
    MONTH(wend),
    LEFT(DATENAME(MONTH, wend), 3),
    CONCAT(LEFT(DATENAME(MONTH, wend), 3), ' ', YEAR(wend)),
    YEAR(wend) * 100 + MONTH(wend),
    DATEPART(ISO_WEEK, wend),
    CASE WHEN (MONTH(wend) = 11 AND DAY(wend) BETWEEN 18 AND 30)      -- Thanksgiving
           OR (MONTH(wend) = 12 AND DAY(wend) BETWEEN 18 AND 31)      -- Christmas
           OR (MONTH(wend) = 7  AND DAY(wend) BETWEEN 1  AND 7)       -- July 4
         THEN 1 ELSE 0 END
FROM wk;
PRINT CONCAT('cpg.Calendar        : ', @@ROWCOUNT, ' weeks');
GO

/* ============================ cpg.Product ================================== */
CREATE TABLE cpg.Product (
    ProductId    int          NOT NULL CONSTRAINT PK_cpg_Product PRIMARY KEY,
    UPC          char(12)     NOT NULL,
    Manufacturer varchar(20)  NOT NULL,
    Brand        varchar(30)  NOT NULL,
    SubBrand     varchar(60)  NOT NULL,
    Category     varchar(12)  NOT NULL,   -- Dog Food | Cat Food | Cat Litter | Dog Treats | Cat Treats
    Form         varchar(8)   NOT NULL,   -- Dry | Wet | Treats | Litter
    LifeStage    varchar(16)  NOT NULL,
    PriceTier    varchar(14)  NOT NULL,   -- Value | Mainstream | Premium | Super-Premium | Therapeutic
    PackSizeLb   decimal(6,2) NOT NULL,
    LaunchWeekKey int         NULL        -- NULL = on shelf before the window
);

CREATE TABLE cpg.ProductPlan (
    ProductId        int          NOT NULL CONSTRAINT PK_cpg_ProductPlan PRIMARY KEY,
    BasePriceUsd     decimal(7,2) NOT NULL,
    BaseVelocity     decimal(9,2) NOT NULL,   -- units/week at a size-10 retailer, 100% ACV
    PromoFrequencyPct int         NOT NULL,
    AnnualTrendPct   decimal(5,1) NOT NULL
);

/* -- brand seed: one row per (brand, category, form, tier); expands to SkuCount SKUs -- */
DECLARE @seed TABLE (
    Manufacturer varchar(20), Brand varchar(30), Category varchar(12), Form varchar(8),
    PriceTier varchar(14), LifeStage varchar(16), SkuCount int,
    PriceLo decimal(7,2), PriceHi decimal(7,2), Velocity decimal(9,2), TrendPct decimal(5,1),
    PromoFreq int, LaunchWk int
);
INSERT @seed VALUES
 ('Nestle Purina','Purina Pro Plan','Dog Food','Dry','Super-Premium','Adult',6,24,74,120,6.0,18,NULL),
 ('Nestle Purina','Purina Pro Plan','Dog Food','Wet','Super-Premium','Adult',3,20,38,300,5.0,16,NULL),
 ('Nestle Purina','Purina Pro Plan','Cat Food','Dry','Super-Premium','Adult',5,18,46,130,7.0,17,NULL),
 ('Nestle Purina','Purina Pro Plan','Cat Food','Wet','Super-Premium','Adult',5,14,32,330,6.0,15,NULL),
 ('Nestle Purina','Pro Plan Vet Diets','Dog Food','Dry','Therapeutic','Adult',4,62,112,38,8.0,6,NULL),
 ('Nestle Purina','Pro Plan Vet Diets','Cat Food','Dry','Therapeutic','Adult',3,58,104,36,8.0,6,NULL),
 ('Nestle Purina','Purina ONE','Dog Food','Dry','Premium','Adult',5,16,44,220,2.0,20,NULL),
 ('Nestle Purina','Purina ONE','Cat Food','Dry','Premium','Adult',4,14,38,230,2.0,20,NULL),
 ('Nestle Purina','Purina Complete','Dog Food','Dry','Premium','Adult',3,17,40,180,22.0,24,80),
 ('Nestle Purina','Beneful','Dog Food','Dry','Mainstream','Adult',4,12,32,300,-3.0,26,NULL),
 ('Nestle Purina','Beneful','Dog Food','Wet','Mainstream','Adult',3,7,15,280,-4.0,24,NULL),
 ('Nestle Purina','Purina Dog Chow','Dog Food','Dry','Value','Adult',4,10,27,430,-6.0,22,NULL),
 ('Nestle Purina','Purina Cat Chow','Cat Food','Dry','Value','Adult',3,9,23,400,-5.0,22,NULL),
 ('Nestle Purina','Friskies','Cat Food','Wet','Value','Adult',6,5,14,520,-2.0,30,NULL),
 ('Nestle Purina','Friskies','Cat Food','Dry','Value','Adult',3,8,21,430,-3.0,26,NULL),
 ('Nestle Purina','Fancy Feast','Cat Food','Wet','Premium','Adult',7,8,22,560,3.0,28,NULL),
 ('Nestle Purina','Purina Tidy Cats','Cat Litter','Litter','Mainstream','All Life Stages',5,12,29,140,1.0,20,NULL),
 ('Nestle Purina','Purina Beggin''','Dog Treats','Treats','Mainstream','Adult',3,7,17,240,4.0,24,NULL),
 ('Nestle Purina','Fancy Feast','Cat Treats','Treats','Premium','Adult',2,4,10,300,4.0,22,NULL),
 ('General Mills','Blue Buffalo','Dog Food','Dry','Super-Premium','Adult',6,30,80,120,14.0,18,NULL),
 ('General Mills','Blue Buffalo','Cat Food','Dry','Super-Premium','Adult',4,24,56,120,12.0,18,NULL),
 ('General Mills','Blue Buffalo Wilderness','Dog Food','Dry','Super-Premium','Adult',3,35,82,95,16.0,16,NULL),
 ('Colgate','Hill''s Science Diet','Dog Food','Dry','Super-Premium','Adult',5,28,74,110,4.0,12,NULL),
 ('Colgate','Hill''s Science Diet','Cat Food','Dry','Super-Premium','Adult',4,26,62,115,4.0,12,NULL),
 ('Colgate','Hill''s Prescription Diet','Dog Food','Dry','Therapeutic','Adult',4,66,122,38,6.0,5,NULL),
 ('Colgate','Hill''s Prescription Diet','Cat Food','Dry','Therapeutic','Adult',3,60,112,36,6.0,5,NULL),
 ('Mars Petcare','Royal Canin','Dog Food','Dry','Super-Premium','Adult',5,32,86,105,7.0,10,NULL),
 ('Mars Petcare','Royal Canin','Cat Food','Dry','Super-Premium','Adult',4,30,72,110,8.0,10,NULL),
 ('Mars Petcare','Royal Canin Veterinary','Cat Food','Dry','Therapeutic','Adult',3,64,116,35,9.0,5,NULL),
 ('Mars Petcare','Pedigree','Dog Food','Dry','Value','Adult',5,10,28,440,-4.0,24,NULL),
 ('Mars Petcare','Pedigree','Dog Food','Wet','Value','Adult',3,5,14,420,-3.0,26,NULL),
 ('Mars Petcare','Iams','Dog Food','Dry','Mainstream','Adult',4,15,40,300,-1.0,22,NULL),
 ('Mars Petcare','Iams','Cat Food','Dry','Mainstream','Adult',3,14,36,300,-1.0,22,NULL),
 ('Mars Petcare','Sheba','Cat Food','Wet','Premium','Adult',4,10,24,480,5.0,26,NULL),
 ('Mars Petcare','Temptations','Cat Treats','Treats','Mainstream','Adult',3,5,12,360,8.0,24,NULL),
 ('Post','Meow Mix','Cat Food','Dry','Value','Adult',3,8,20,430,-2.0,24,NULL),
 ('Post','9Lives','Cat Food','Wet','Value','Adult',3,4,12,440,-5.0,26,NULL),
 ('Post','Rachael Ray Nutrish','Dog Food','Dry','Premium','Adult',3,18,44,190,0.0,22,NULL),
 ('All Other','Wellness','Dog Food','Dry','Super-Premium','Adult',3,32,78,90,6.0,14,NULL),
 ('All Other','Merrick','Dog Food','Dry','Super-Premium','Adult',3,34,80,80,5.0,14,NULL),
 ('Private Label','Private Label','Dog Food','Dry','Value','Adult',5,8,23,360,10.0,14,NULL),
 ('Private Label','Private Label','Cat Food','Dry','Value','Adult',4,7,20,360,9.0,14,NULL),
 ('Private Label','Private Label','Cat Litter','Litter','Value','All Life Stages',3,8,19,150,7.0,12,NULL);

;WITH s AS (SELECT *, SeedId = ROW_NUMBER() OVER (ORDER BY Manufacturer, Brand, Form, PriceTier) FROM @seed),
expanded AS (
    SELECT s.*, n = g.value,
           h = ABS(CHECKSUM(HASHBYTES('MD5', CONCAT(s.SeedId, '-', g.value))))
    FROM s CROSS APPLY GENERATE_SERIES(1, s.SkuCount) AS g
)
SELECT
    ProductId  = ROW_NUMBER() OVER (ORDER BY SeedId, n),
    Manufacturer, Brand, Category, Form, LaunchWk,
    PriceTier,
    PackSizeLb = CAST(CASE Form
        WHEN 'Dry'    THEN CHOOSE(h % 6 + 1, 3.5, 4.0, 5.0, 13.0, 24.0, 30.0)
        WHEN 'Wet'    THEN CHOOSE(h % 4 + 1, 0.20, 0.35, 0.75, 1.10)
        WHEN 'Treats' THEN CHOOSE(h % 3 + 1, 0.375, 1.0, 1.875)
        ELSE               CHOOSE(h % 3 + 1, 20.0, 35.0, 40.0) END AS decimal(6,2)),
    LifeStageSku = CASE WHEN h % 10 < 6 THEN LifeStage
                        WHEN h % 10 < 8 THEN 'Puppy/Kitten'
                        WHEN h % 10 < 9 THEN 'Senior'
                        ELSE 'All Life Stages' END,
    Descriptor = CHOOSE(h % 12 + 1,
        'Chicken & Rice','Salmon & Sweet Potato','Sensitive Skin & Stomach','Shredded Blend',
        'Weight Management','Indoor','Large Breed','Small Breed','Grain Free','High Protein',
        'Gravy Lovers','Classic Pate'),
    BasePriceUsd = CAST(PriceLo + (h % 1000) / 1000.0 * (PriceHi - PriceLo) AS decimal(7,2)),
    BaseVelocity = CAST(Velocity * (0.7 + (h % 60) / 100.0) AS decimal(9,2)),
    PromoFrequencyPct = PromoFreq + (h % 7) - 3,
    AnnualTrendPct = CAST(TrendPct + ((h % 60) - 30) / 10.0 AS decimal(5,1))
INTO #sku
FROM expanded;

INSERT cpg.Product (ProductId, UPC, Manufacturer, Brand, SubBrand, Category, Form, LifeStage,
                    PriceTier, PackSizeLb, LaunchWeekKey)
SELECT
    ProductId,
    RIGHT('00000000000' + CAST(ProductId * 37 + 100000 AS varchar(12)), 12),
    Manufacturer, Brand,
    CONCAT(Brand, ' ', Descriptor),
    Category, Form, LifeStageSku, PriceTier, PackSizeLb, LaunchWk
FROM #sku;
PRINT CONCAT('cpg.Product         : ', @@ROWCOUNT, ' SKUs');

INSERT cpg.ProductPlan (ProductId, BasePriceUsd, BaseVelocity, PromoFrequencyPct, AnnualTrendPct)
SELECT ProductId, BasePriceUsd, BaseVelocity,
       CASE WHEN PromoFrequencyPct < 4 THEN 4 WHEN PromoFrequencyPct > 34 THEN 34 ELSE PromoFrequencyPct END,
       AnnualTrendPct
FROM #sku;
PRINT CONCAT('cpg.ProductPlan     : ', @@ROWCOUNT, ' rows');

DROP TABLE #sku;
GO

/* ============================ cpg.Distribution ============================= */
CREATE TABLE cpg.Distribution (
    ProductId       int          NOT NULL,
    RetailerId      int          NOT NULL,
    BaseACV         decimal(5,2) NOT NULL,   -- % ACV carrying the SKU at week 1
    ACVTrendPerYear decimal(5,2) NOT NULL,
    CONSTRAINT PK_cpg_Distribution PRIMARY KEY (ProductId, RetailerId),
    CONSTRAINT FK_cpg_Dist_Prod FOREIGN KEY (ProductId)  REFERENCES cpg.Product (ProductId),
    CONSTRAINT FK_cpg_Dist_Ret  FOREIGN KEY (RetailerId) REFERENCES cpg.Retailer (RetailerId)
);

;WITH elig AS (
    SELECT p.ProductId, p.Manufacturer, p.Brand, p.PriceTier, p.Form,
           r.RetailerId, r.Channel, r.ACVWeight,
           h = ABS(CHECKSUM(HASHBYTES('MD5', CONCAT('dist', p.ProductId, '-', r.RetailerId))))
    FROM cpg.Product p
    CROSS JOIN cpg.Retailer r
    WHERE (p.Brand <> 'Private Label' AND (
              (p.PriceTier = 'Therapeutic'   AND r.Channel IN ('Pet Specialty','E-Commerce'))
           OR (p.PriceTier = 'Super-Premium' AND r.Channel IN ('Pet Specialty','E-Commerce','Mass','Farm & Ranch'))
           OR (p.PriceTier = 'Premium'       AND r.Channel IN ('Pet Specialty','E-Commerce','Mass','Grocery','Club'))
           OR (p.PriceTier = 'Mainstream'    AND r.Channel IN ('Mass','Grocery','E-Commerce','Club','Pet Specialty'))
           OR (p.PriceTier = 'Value'         AND r.Channel IN ('Mass','Grocery','Club','E-Commerce','Farm & Ranch'))
           OR (p.Form = 'Litter'             AND r.Channel = 'Pet Specialty')))
       OR (p.Brand = 'Private Label' AND r.RetailerId IN (1,6,7,10,11,12,13))
),
plranked AS (
    SELECT *, plrank = ROW_NUMBER() OVER (PARTITION BY ProductId ORDER BY h)
    FROM elig WHERE Brand = 'Private Label'
),
kept AS (
    SELECT ProductId, Manufacturer, PriceTier, RetailerId, ACVWeight, h
    FROM elig WHERE Brand <> 'Private Label' AND h % 100 < 82
    UNION ALL
    SELECT ProductId, Manufacturer, PriceTier, RetailerId, ACVWeight, h
    FROM plranked WHERE plrank <= 2 + h % 2
)
INSERT cpg.Distribution (ProductId, RetailerId, BaseACV, ACVTrendPerYear)
SELECT
    ProductId, RetailerId,
    BaseACV = CAST(CASE WHEN v.acv < 18 THEN 18 WHEN v.acv > 98 THEN 98 ELSE v.acv END AS decimal(5,2)),
    ACVTrendPerYear = CAST(CASE
        WHEN Manufacturer = 'General Mills'  THEN 3.5 + (h % 5)
        WHEN Manufacturer = 'Private Label'  THEN 3.0 + (h % 4)
        WHEN PriceTier = 'Value' AND Manufacturer = 'Nestle Purina' THEN -3.0 - (h % 3)
        ELSE (h % 7) - 3 END AS decimal(5,2))
FROM kept
CROSS APPLY (SELECT acv =
        35.0 + (ACVWeight * 1.3)
        + CASE Manufacturer WHEN 'Nestle Purina' THEN 15 WHEN 'Mars Petcare' THEN 12
                            WHEN 'General Mills' THEN 8  WHEN 'Colgate' THEN 6
                            WHEN 'Private Label' THEN 12 ELSE 0 END
        + ((h / 100) % 20) - 10) v;
PRINT CONCAT('cpg.Distribution    : ', @@ROWCOUNT, ' product-retailer pairs');
GO

/* ============================ cpg.SalesFact =============================== */
CREATE TABLE cpg.SalesFact (
    ProductId          int           NOT NULL,
    RetailerId         int           NOT NULL,
    WeekKey            int           NOT NULL,
    DollarSales        decimal(12,2) NOT NULL,
    UnitSales          int           NOT NULL,
    VolumeSalesLb      decimal(12,2) NOT NULL,
    ACVDistribution    decimal(5,2)  NOT NULL,
    BaseDollars        decimal(12,2) NOT NULL,
    IncrementalDollars decimal(12,2) NOT NULL,
    BaseUnits          int           NOT NULL,
    AvgSellingPrice    decimal(7,2)  NOT NULL,
    BasePrice          decimal(7,2)  NOT NULL,
    AnyPromo           bit           NOT NULL,
    FeatureFlag        bit           NOT NULL,
    DisplayFlag        bit           NOT NULL,
    PriceReductionFlag bit           NOT NULL,
    CONSTRAINT PK_cpg_SalesFact PRIMARY KEY (ProductId, RetailerId, WeekKey)
);

;WITH base AS (
    SELECT d.ProductId, d.RetailerId, d.BaseACV, d.ACVTrendPerYear,
           pp.BasePriceUsd, pp.BaseVelocity, pp.PromoFrequencyPct, pp.AnnualTrendPct,
           p.Form, p.PackSizeLb, p.LaunchWeekKey, r.ACVWeight
    FROM cpg.Distribution d
    JOIN cpg.ProductPlan pp ON pp.ProductId  = d.ProductId
    JOIN cpg.Product p      ON p.ProductId   = d.ProductId
    JOIN cpg.Retailer r     ON r.RetailerId  = d.RetailerId
),
grid AS (
    SELECT b.*, c.WeekKey, c.WeekIndex, c.WeekOfYear, c.MonthNumber,
           yrs = (c.WeekIndex - 1) / 52.0,
           promoBlock = (c.WeekIndex - 1) / 3,
           hWeek = ABS(CHECKSUM(HASHBYTES('MD5', CONCAT(b.ProductId, '|', b.RetailerId, '|', c.WeekKey))))
    FROM base b
    JOIN cpg.Calendar c ON b.LaunchWeekKey IS NULL OR c.WeekKey >= b.LaunchWeekKey
),
calc AS (
    SELECT g.*,
        hBlock = ABS(CHECKSUM(HASHBYTES('MD5', CONCAT(g.ProductId, '|', g.RetailerId, '|B', g.promoBlock)))),
        acvWk  = CASE WHEN a.v < 0 THEN 0 WHEN a.v > 99 THEN 99 ELSE a.v END,
        seasonal = 1.0
                 + CASE WHEN g.Form = 'Treats' AND g.MonthNumber IN (11,12) THEN 0.22 ELSE 0 END
                 + 0.03 * SIN(2 * PI() * g.WeekOfYear / 52.0),
        trendMult = POWER(1.0 + g.AnnualTrendPct / 100.0, g.yrs),
        noise = 0.80 + (g.hWeek % 40) / 100.0
    FROM grid g
    CROSS APPLY (SELECT v = g.BaseACV + g.ACVTrendPerYear * g.yrs + ((g.hWeek % 7) - 3)) a
),
promo AS (
    SELECT c.*,
        isPromo = CASE WHEN c.hBlock % 100 < c.PromoFrequencyPct THEN 1 ELSE 0 END,
        ptype   = c.hBlock % 4,
        depth   = 0.10 + (c.hBlock % 22) / 100.0
    FROM calc c
),
units AS (
    SELECT p.*,
        baseUnits = CASE WHEN p.acvWk <= 0 THEN 0
            ELSE CAST(ROUND(p.BaseVelocity * (p.ACVWeight / 10.0) * (p.acvWk / 100.0)
                            * p.seasonal * p.trendMult * p.noise, 0) AS int) END,
        lift = CASE WHEN p.isPromo = 0 THEN 1.0
            ELSE (CASE p.ptype WHEN 0 THEN 1.30 WHEN 1 THEN 1.95 WHEN 2 THEN 1.70 ELSE 2.80 END)
                 * (1.0 + p.depth * 1.2) END,
        asp = CASE WHEN p.isPromo = 0 THEN p.BasePriceUsd * (0.99 + (p.hWeek % 20) / 1000.0)
                   ELSE p.BasePriceUsd * (1.0 - p.depth * 0.68) END
    FROM promo p
),
fin AS (
    SELECT u.*,
        aspR = CAST(u.asp AS decimal(7,2)),
        sold = CASE WHEN u.isPromo = 1 THEN CAST(ROUND(u.baseUnits * u.lift, 0) AS int) ELSE u.baseUnits END
    FROM units u
    WHERE u.baseUnits > 0
)
INSERT cpg.SalesFact (ProductId, RetailerId, WeekKey, DollarSales, UnitSales, VolumeSalesLb,
    ACVDistribution, BaseDollars, IncrementalDollars, BaseUnits, AvgSellingPrice, BasePrice,
    AnyPromo, FeatureFlag, DisplayFlag, PriceReductionFlag)
SELECT
    ProductId, RetailerId, WeekKey,
    CAST(sold * aspR AS decimal(12,2)),
    sold,
    CAST(sold * PackSizeLb AS decimal(12,2)),
    CAST(acvWk AS decimal(5,2)),
    CAST(baseUnits * BasePriceUsd AS decimal(12,2)),
    CAST(CASE WHEN sold * aspR - baseUnits * BasePriceUsd < 0 THEN 0
              ELSE sold * aspR - baseUnits * BasePriceUsd END AS decimal(12,2)),
    baseUnits,
    aspR,
    CAST(BasePriceUsd AS decimal(7,2)),
    isPromo,
    CASE WHEN isPromo = 1 AND ptype IN (1, 3) THEN 1 ELSE 0 END,
    CASE WHEN isPromo = 1 AND ptype IN (2, 3) THEN 1 ELSE 0 END,
    isPromo
FROM fin;
PRINT CONCAT('cpg.SalesFact       : ', @@ROWCOUNT, ' rows');

CREATE INDEX IX_cpg_SalesFact_Week ON cpg.SalesFact (WeekKey)  INCLUDE (ProductId, RetailerId, DollarSales, UnitSales, VolumeSalesLb, BaseDollars, IncrementalDollars, AnyPromo);
CREATE INDEX IX_cpg_SalesFact_Prod ON cpg.SalesFact (ProductId) INCLUDE (RetailerId, WeekKey, DollarSales, UnitSales, VolumeSalesLb, BaseDollars, IncrementalDollars, ACVDistribution, AnyPromo);
GO

PRINT '';
SELECT Manufacturer, SKUs = COUNT(*) FROM cpg.Product GROUP BY Manufacturer ORDER BY SKUs DESC;
SELECT TotalDollarSales = CAST(SUM(DollarSales)/1e6 AS decimal(10,1)),
       Weeks = COUNT(DISTINCT WeekKey), Rows = COUNT(*),
       PromoShareOfDollars = CAST(100.0 * SUM(CASE WHEN AnyPromo=1 THEN DollarSales ELSE 0 END) / SUM(DollarSales) AS decimal(5,1))
FROM cpg.SalesFact;
GO

PRINT 'Category generation complete.';
GO
