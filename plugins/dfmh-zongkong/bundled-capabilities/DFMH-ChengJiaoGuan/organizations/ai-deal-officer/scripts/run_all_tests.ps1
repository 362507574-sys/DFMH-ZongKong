$ErrorActionPreference = 'Stop'

$organizationRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Resolve-Path (Join-Path $organizationRoot '..\..')
$organizationTests = Get-ChildItem -LiteralPath (Join-Path $organizationRoot 'tests') -Filter '*.test.mjs' |
    Sort-Object FullName |
    ForEach-Object { $_.FullName }

& node --test $organizationTests
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& node (Join-Path $organizationRoot 'scripts\organization_self_check.mjs')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$rootTests = @(
    (Join-Path $projectRoot 'tests\control_center_deal_officer_design_test.mjs'),
    (Join-Path $projectRoot 'tests\control_center_deal_officer_implementation_test.mjs'),
    (Join-Path $projectRoot 'tests\control_center_registry_test.mjs'),
    (Join-Path $projectRoot 'tests\control_center_organization_router_test.mjs'),
    (Join-Path $projectRoot 'tests\control_center_project_context_test.mjs'),
    (Join-Path $projectRoot 'tests\control_center_project_artifact_store_test.mjs'),
    (Join-Path $projectRoot 'tests\control_center_project_contract_test.mjs'),
    (Join-Path $projectRoot 'tests\control_center_project_workspace_self_check_test.mjs')
)

& node --test $rootTests
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Output 'PASS: AI deal officer one-click tests completed.'
