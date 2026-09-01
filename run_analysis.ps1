<#
    run_analysis.ps1 -- build the pet-food category dataset and run the analysis.

      1. generate the synthetic syndicated POS data   (sql\00)
      2. build the analytics layer                     (sql\01)
      3. validate                                      (sql\02)
      4. guided tour                                   (sql\03)

    Needs SQL Server with the Chinook database (the cpg schema is created there)
    and sqlcmd. Step 1 takes ~30s.
    Run:  .\run_analysis.ps1

    For the Power BI layer, then run  powerbi\01_semantic_views.sql  and follow
    powerbi\model-guide.md / report-guide.md.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
function Sql($rel) { & "$root\q.ps1" -File (Join-Path $root $rel) | Write-Host }
function Head($n)  { Write-Host "`n### $n" -ForegroundColor Cyan }

Head '1. generate synthetic category data (~30s)'; Sql 'sql\00_generate_category.sql'
Head '2. analytics layer';                         Sql 'sql\01_analytics_layer.sql'
Head '3. validation';                              Sql 'sql\02_validate.sql'
Head '4. guided tour';                             Sql 'sql\03_demo.sql'
Head '5. Power BI semantic views';                 Sql 'powerbi\01_semantic_views.sql'

Write-Host "`nDone. Every check in step 3 should read PASS." -ForegroundColor Green
Write-Host "For the dashboard, open Power BI Desktop and follow powerbi\model-guide.md." -ForegroundColor Green
