$Preview = $false
$env:PSExecutionPolicyPreference = "Bypass"

# =========================================
# Lab 662 Skillable Foundry deployment (azd)
# azd provisions the project, both model deployments and the Caldova agents from a generated azure.yaml.
# The script then adds what azd does not manage: guardrail policy and agents, learner roles, traces and evals.
# =========================================
$logPath = "C:\Users\LabUser\Desktop\lifecycle-lab662.log"
Start-Transcript -Path $logPath -Force

try {
    # === Variables ===
    # UPDATED: subscription pool / resource group / portal credential tokens no longer exist on
    # this profile. Everything now comes from the hydrated tenant's credential pool.
    $appId     = "@lab.CloudCredential(AITour27M365E7).ClientId"
    $appSecret = "@lab.CloudCredential(AITour27M365E7).ClientSecret"
    $tenantId  = "@lab.CloudCredential(AITour27M365E7).TenantId"
    $subId     = "@lab.CloudCredential(AITour27M365E7).SubscriptionId"
    $region    = "eastus2"   # UPDATED: was the Skillable RG location; pick a region with quota for both models
    $envName   = "ignite@lab.LabInstance.Id"
    $userUpn   = "@lab.CloudCredential(AITour27M365E7).Username"   # MeganB

    # UPDATED: fail fast if any credential-pool token didn't resolve
    foreach ($v in $appId, $appSecret, $tenantId, $subId, $userUpn) {
        if ($v -like '@lab.*') { throw "Replacement token did not resolve: $v" }
    }

    $labDir     = "D:\LabFiles\lab662\foundry-project"  # lab files saved on the VM
    $workDir    = "D:\LabFiles\lab662\azd-project"      # generated azd project
    $agentModel = "gpt-5.4-mini"                      # model and deployment name used by the agents
    $judgeModel = "gpt-6-sol"                         # model and deployment name used by the evaluators

    $ErrorActionPreference = "Stop"

    # Run an external command and preserve its full output in the lifecycle log.
    function Invoke-External($label, [ScriptBlock]$cmd) {
        Write-Host ">>> $label"
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = & $cmd 2>&1 | ForEach-Object { Write-Host $_; $_ }
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prev
        }
        if ($exitCode -ne 0) { throw "$label failed (exit $exitCode): $($output | Out-String)" }
    }

    function Initialize-AzdExtensions {
        Invoke-External "install microsoft.foundry and its dependencies" {
            azd extension install microsoft.foundry --force --no-prompt
        }
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = & azd extension list --installed --output json --no-prompt 2>$null
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $prev
        }
        if ($exitCode -ne 0) {
            throw "Could not verify installed azd extensions (exit $exitCode): $($output | Out-String)"
        }
        $installed = @($output | Out-String | ConvertFrom-Json)
        foreach ($extensionId in "microsoft.foundry", "azure.ai.agents", "azure.ai.projects") {
            $extension = $installed | Where-Object { $_.id -eq $extensionId -and $_.installedVersion }
            if (-not $extension) {
                throw "Required azd extension '$extensionId' was not installed by microsoft.foundry."
            }
            Write-Host "Verified azd extension $extensionId $($extension.installedVersion)"
        }
    }

    function Get-AzdEnvValue([string[]]$names, [string]$label) {
        foreach ($name in $names) {
            $output = & azd env get-value $name -e $envName 2>$null
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0) {
                $value = ($output | Out-String).Trim()
                if ($value) { return $value }
            }
        }

        throw "azd did not publish $label (checked: $($names -join ', '))."
    }

    function Invoke-Arm([string]$method, [string]$path, $body = $null) {
        $parameters = @{ Method = $method; Path = $path }
        if ($null -ne $body) { $parameters.Payload = ConvertTo-Json -InputObject $body -Depth 30 -Compress }
        $response = Invoke-AzRestMethod @parameters
        if ($response.StatusCode -ge 400) { throw "$method $path returned $($response.StatusCode): $($response.Content)" }
        if ($response.Content) { return ($response.Content | ConvertFrom-Json) }
    }

    function Wait-Provisioned([string]$path) {
        for ($attempt = 1; $attempt -le 90; $attempt++) {
            $state = (Invoke-Arm "GET" $path).properties.provisioningState
            if ($state -eq "Succeeded") { return }
            if ($state -in "Failed", "Canceled") { throw "$path ended in state $state." }
            Start-Sleep -Seconds 5
        }
        throw "$path did not finish provisioning."
    }

    function Grant-Role($principalId, $roleId, $scope, $label) {
        $existing = Get-AzRoleAssignment -ObjectId $principalId -RoleDefinitionId $roleId -Scope $scope -ErrorAction Stop |
            Where-Object { $_.Scope -eq $scope }
        if ($existing) {
            Write-Host "Skip (already exists): $label for $principalId"
            return
        }
        try {
            New-AzRoleAssignment -RoleDefinitionId $roleId -ObjectId $principalId -Scope $scope -ErrorAction Stop | Out-Null
            Write-Host "Granted $label to $principalId"
        } catch {
            if ($_.Exception.Message -match "already exists|RoleAssignmentExists") {
                Write-Host "Skip (already exists): $label for $principalId"
            } else { throw }
        }
    }

    # Retry until a newly provisioned resource is available through ARM.
    function Invoke-WithRetry([ScriptBlock]$sb, [string]$label, [int]$maxAttempts = 12, [int]$delaySec = 15) {
        for ($i = 1; $i -le $maxAttempts; $i++) {
            try {
                $result = & $sb
                if ($result) { return $result }
                Write-Host "  $label attempt $i/${maxAttempts}: empty result, retrying in ${delaySec}s..."
            } catch {
                Write-Host "  $label attempt $i/${maxAttempts}: $($_.Exception.Message)"
                if ($i -eq $maxAttempts) { throw }
            }
            Start-Sleep -Seconds $delaySec
        }
        throw "$label did not return a result after $maxAttempts attempts."
    }

    function Invoke-AzdUpWithRetry([int]$maxAttempts = 3, [int]$delaySec = 30) {
        for ($i = 1; $i -le $maxAttempts; $i++) {
            Write-Host ">>> azd up (attempt $i/$maxAttempts)"
            $prev = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $output = & azd up -e $envName --no-prompt 2>&1
                $exitCode = $LASTEXITCODE
                $output | ForEach-Object { Write-Host $_ }
            } finally {
                $ErrorActionPreference = $prev
            }

            if ($exitCode -eq 0) { return }

            $outputText = $output | Out-String
            $isTransientConflict = $outputText -match "RequestConflict|Another operation is in progress"
            if (-not $isTransientConflict -or $i -eq $maxAttempts) {
                throw "azd up failed (exit $exitCode)."
            }

            Write-Host "Azure is still completing an operation on the Foundry account. Retrying in ${delaySec}s..."
            Start-Sleep -Seconds $delaySec
        }
    }

    $azModules = [ordered]@{
        "Az.Accounts"          = "5.5.3"
        "Az.Resources"         = "10.2.1"
        "Az.CognitiveServices" = "1.17.1"
    }
    foreach ($moduleName in $azModules.Keys) {
        Install-Module -Name $moduleName `
            -RequiredVersion $azModules[$moduleName] `
            -Repository PSGallery `
            -Scope CurrentUser `
            -Force `
            -AllowClobber `
            -ErrorAction Stop
    }

    foreach ($moduleName in $azModules.Keys) {
        $moduleVersion = [version]$azModules[$moduleName]
        $module = Get-Module -ListAvailable -Name $moduleName |
            Where-Object { $_.Version -eq $moduleVersion } |
            Select-Object -First 1
        if (-not $module) {
            throw "Required Azure PowerShell module '$moduleName' version '$moduleVersion' was not installed."
        }
        Import-Module -Name $module.Path -RequiredVersion $moduleVersion -ErrorAction Stop
        Write-Host "Loaded $moduleName $($module.Version) from $($module.Path)"
    }

    # === Authentication ===
    Write-Host ">>> Connect-AzAccount"
    $securePwd = ConvertTo-SecureString $appSecret -AsPlainText -Force
    $psCred    = New-Object System.Management.Automation.PSCredential ($appId, $securePwd)
    Connect-AzAccount -ServicePrincipal -Tenant $tenantId -Credential $psCred -Subscription $subId -SkipContextPopulation | Out-Null

    # UPDATED: imported subscription has no resource providers registered. Register up front
    # (and wait) so azd / the ARM PUTs below don't race first-use auto-registration.
    $providers = "Microsoft.CognitiveServices", "Microsoft.OperationalInsights", "Microsoft.Insights",
                 "Microsoft.Storage", "Microsoft.Search", "Microsoft.KeyVault", "Microsoft.BotService"
    foreach ($ns in $providers) {
        $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1).RegistrationState
        if ($state -ne "Registered") {
            Write-Host "Registering resource provider $ns ($state)"
            Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null
        }
    }
    foreach ($ns in $providers) {
        for ($i = 1; $i -le 40; $i++) {
            $state = (Get-AzResourceProvider -ProviderNamespace $ns | Select-Object -First 1).RegistrationState
            if ($state -eq "Registered") { break }
            if ($i -eq 40) { throw "Resource provider $ns still '$state' after 10 minutes." }
            Start-Sleep -Seconds 15
        }
        Write-Host "Resource provider $ns registered"
    }

    # Azure tooling prerequisites

    # Azure CLI
    if (Get-Command az -ErrorAction SilentlyContinue) {
        winget upgrade --exact --id Microsoft.AzureCLI `
            --accept-package-agreements `
            --accept-source-agreements
    }
    else {
        winget install --exact --id Microsoft.AzureCLI --scope machine `
            --accept-package-agreements `
            --accept-source-agreements
    }

    # Azure Developer CLI - force install/update latest
    $azdRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Azure/azure-dev/releases/latest" -ErrorAction Stop
    if ($azdRelease.tag_name -notmatch '^azure-dev-cli_(\d+\.\d+\.\d+)$') {
        throw "Could not determine the latest stable Azure Developer CLI version."
    }
    $azdLatestVersion = [version]$Matches[1]
    $azdInstallDir = Join-Path $env:LOCALAPPDATA "Programs\Azure Dev CLI"
    $azdExe = Join-Path $azdInstallDir "azd.exe"
    $azdInstaller = Join-Path ([IO.Path]::GetTempPath()) ("install-azd-{0}.ps1" -f [guid]::NewGuid())

    try {
        Invoke-RestMethod -Uri "https://aka.ms/install-azd.ps1" -OutFile $azdInstaller -ErrorAction Stop
        powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $azdInstaller `
            -Version $azdLatestVersion.ToString() -InstallFolder $azdInstallDir -NoTelemetry

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install/update Azure Developer CLI to $azdLatestVersion (exit $LASTEXITCODE)."
        }
    }
    finally {
        Remove-Item -Path $azdInstaller -Force -ErrorAction SilentlyContinue
    }

    # Refresh PATH
    $env:Path = $azdInstallDir + ";" +
                [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")

    # Verify
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI (az) is not available."
    }

    if (-not (Test-Path -LiteralPath $azdExe -PathType Leaf)) {
        throw "Updated Azure Developer CLI was not found at '$azdExe'."
    }
    $azdCommand = Get-Command azd -ErrorAction Stop
    if ($azdCommand.Source -ne $azdExe) {
        throw "azd resolves to '$($azdCommand.Source)' instead of '$azdExe'."
    }

    $azdVersionOutput = & $azdExe version
    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify the updated Azure Developer CLI version."
    }
    if (($azdVersionOutput | Out-String) -notmatch '\bazd version (\d+\.\d+\.\d+)\b') {
        throw "Unrecognized Azure Developer CLI version output: $azdVersionOutput"
    }
    $azdInstalledVersion = [version]$Matches[1]
    if ($azdInstalledVersion -ne $azdLatestVersion) {
        throw "Expected Azure Developer CLI $azdLatestVersion but found $azdInstalledVersion at '$azdExe'."
    }
    Write-Host "Verified Azure Developer CLI $azdInstalledVersion at '$azdExe'."

    az version
    $env:AZD_SKIP_FIRST_RUN = "true"
    $env:AZD_SKIP_UPDATE_CHECK = "true"
    Invoke-External "verify azd version" { azd version }
    Initialize-AzdExtensions

    # Resolve lab user object ID
    $userId  = $null
    $retries = 0

    while (-not $userId -and $retries -lt 10) {
        $retries++
        try {
            $user = Get-AzADUser `
                -UserPrincipalName $userUpn `
                -ErrorAction Stop

            if ($user) {
                $userId = $user.Id
            }
        }
        catch {
            Write-Host "User lookup attempt ${retries}: $($_.Exception.Message)"
        }
        if (-not $userId -and $retries -lt 10) {
            Start-Sleep -Seconds 15
        }
    }

    if (-not $userId) {
        throw "Could not resolve the deployment user after $retries attempts."
    }
    Write-Host "userId = $userId"

    # === Generate the azd project from the saved agent definitions ===
    $env:AZD_SKIP_FIRST_RUN = "true"
    $env:AZD_SKIP_UPDATE_CHECK = "true"

    # Do not let any AZURE_RESOURCE_GROUP left on the image override the
    # provider-managed resource group for this azd environment.
    Remove-Item Env:AZURE_RESOURCE_GROUP -ErrorAction SilentlyContinue

    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    Set-Location $workDir

    # The guardrail agents (rai_config) are created after azd, once the policy exists.
    $agentFiles = Get-ChildItem -Path (Join-Path $labDir "agents") -Filter *.json |
        ForEach-Object { Get-Content -Raw -Path $_.FullName | ConvertFrom-Json }
    $azdAgents       = @($agentFiles | Where-Object { -not $_.definition.rai_config })
    $guardrailAgents = @($agentFiles | Where-Object { $_.definition.rai_config })

    # JSON strings are valid double-quoted YAML scalars, so instructions are written as JSON.
    $yaml = New-Object System.Collections.Generic.List[string]
    $yaml.Add("name: lab662")
    $yaml.Add("services:")
    $yaml.Add("    ai-project:")
    $yaml.Add("        host: azure.ai.project")
    $yaml.Add("        deployments:")
    foreach ($m in @(@{ Name = $agentModel; Version = "2026-03-17" }, @{ Name = $judgeModel; Version = "2026-09-22" })) {
        $yaml.Add("            - model:")
        $yaml.Add("                format: OpenAI")
        $yaml.Add("                name: $($m.Name)")
        $yaml.Add("                version: `"$($m.Version)`"")
        $yaml.Add("              name: $($m.Name)")
        $yaml.Add("              sku:")
        $yaml.Add("                capacity: 100")
        $yaml.Add("                name: GlobalStandard")
    }
    foreach ($a in $azdAgents) {
        $yaml.Add("    $($a.name):")
        $yaml.Add("        project: .")
        $yaml.Add("        host: azure.ai.agent")
        $yaml.Add("        uses:")
        $yaml.Add("            - ai-project")
        $yaml.Add("        kind: prompt")
        $yaml.Add("        model: $agentModel")
        $yaml.Add("        name: $($a.name)")
        $yaml.Add("        instructions: $($a.definition.instructions | ConvertTo-Json -Compress)")
    }
    $yaml.Add("infra:")
    $yaml.Add("    provider: microsoft.foundry")
    Set-Content -Path (Join-Path $workDir "azure.yaml") -Value $yaml -Encoding UTF8

    # === azd up ===
    Invoke-External "verify azd version" {
        azd version
    }
    Invoke-External "azd auth login" {
        azd auth login --client-id $appId --client-secret $appSecret --tenant-id $tenantId
    }
    $environmentFile = Join-Path $workDir (Join-Path ".azure" (Join-Path $envName ".env"))
    if (Test-Path -LiteralPath $environmentFile) {
        Invoke-External "azd env select" { azd env select $envName --no-prompt }
    }
    else {
        Invoke-External "azd env new" {
            azd env new $envName --location $region --subscription $subId --no-prompt
        }
    }

    Invoke-External "configure azd tenant" {
        azd env set AZURE_TENANT_ID $tenantId -e $envName
    }
    if ($Preview) {
        Invoke-External "azd provision preview" {
            azd provision --preview -e $envName --no-prompt
        }
        Write-Host ">>> Preview complete. No resources provisioned; role assignments, replay, and evaluations skipped."
        return
    }
    Invoke-AzdUpWithRetry

    # === Post-deploy role assignments ===
    $foundryUserRoleId           = "53ca6127-db72-4b80-b1b0-d745d6d5456d"  # Foundry User
    $foundryProjectManagerRoleId = "eadc314b-1a2d-4efa-be10-5d325db5065e"  # Foundry Project Manager
    $openAIUserRoleId            = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd"  # Cognitive Services OpenAI User
    $readerRoleId                = "acdd72a7-3385-48ef-bd42-f606fba81ae7"  # Reader
    $monitoringReaderRoleId      = "43d0d8ad-25c7-4714-9337-8ba259a9fe05"  # Monitoring Reader
    $policyContributorRoleId     = "36243c78-bf99-498c-9df9-86d9f8d28608"  # Resource Policy Contributor
    $contributorRoleId           = "b24988ac-6180-42a0-ab88-20f7382dd24c"  # Contributor (includes Microsoft.BotService/botServices/write)

    $azdRg = Get-AzdEnvValue @("AZURE_RESOURCE_GROUP") "the resource group"
    Write-Host "azd resource group: $azdRg"

    $aiProjectId = Get-AzdEnvValue @("AZURE_AI_PROJECT_ID") "the Foundry project resource ID"
    $accountPrefix = "/subscriptions/$subId/resourceGroups/$azdRg/providers/Microsoft.CognitiveServices/accounts/"
    if ($aiProjectId -notmatch "^($([regex]::Escape($accountPrefix))[^/]+)/projects/[^/]+$") {
        throw "azd published a project resource ID outside the deployment subscription/resource group: '$aiProjectId'."
    }
    $aiResourceId = $Matches[1]
    $aiResource = Invoke-WithRetry {
        Get-AzResource -ResourceId $aiResourceId -ErrorAction Stop
    } "Get Foundry account"
    Write-Host "aiResourceId = $aiResourceId"

    $aiProject = Invoke-WithRetry {
        Get-AzResource -ResourceId $aiProjectId -ErrorAction Stop
    } "Get Foundry project"

    $armVersion = "2025-06-01"
    $rgPath = "/subscriptions/$subId/resourceGroups/$azdRg/providers"
    $lawPath = "$rgPath/Microsoft.OperationalInsights/workspaces/log-lab662"
    Invoke-Arm "PUT" "$lawPath`?api-version=2022-10-01" @{
        location = $aiResource.Location
        properties = @{ sku = @{ name = "PerGB2018" }; retentionInDays = 30 }
    } | Out-Null
    Wait-Provisioned "$lawPath`?api-version=2022-10-01"

    $appiPath = "$rgPath/Microsoft.Insights/components/appi-lab662"
    Invoke-Arm "PUT" "$appiPath`?api-version=2020-02-02" @{
        location = $aiResource.Location
        kind = "web"
        properties = @{ Application_Type = "web"; WorkspaceResourceId = $lawPath }
    } | Out-Null
    Wait-Provisioned "$appiPath`?api-version=2020-02-02"
    $appiConnectionString = (Invoke-Arm "GET" "$appiPath`?api-version=2020-02-02").properties.ConnectionString
    Invoke-Arm "PUT" "$aiProjectId/connections/appi-lab662?api-version=$armVersion" @{
        properties = @{
            category = "AppInsights"
            target = $appiPath
            authType = "ApiKey"
            isSharedToAll = $true
            credentials = @{ key = $appiConnectionString }
            metadata = @{ ApiType = "Azure"; ResourceId = $appiPath }
        }
    } | Out-Null
    Write-Host "Connected Application Insights appi-lab662 to project $aiProjectId"

    Grant-Role $userId $foundryUserRoleId           $aiProjectId  "Foundry User (learner)"
    Grant-Role $userId $foundryProjectManagerRoleId $aiProjectId  "Foundry Project Manager (learner)"
    Grant-Role $userId $openAIUserRoleId            $aiResourceId "Cognitive Services OpenAI User (learner)"
    Grant-Role $userId $readerRoleId                "/subscriptions/$subId" "Reader (learner, cost overview)"
    Grant-Role $userId $monitoringReaderRoleId      "/subscriptions/$subId" "Monitoring Reader (learner, metrics)"
    Grant-Role $userId $policyContributorRoleId     "/subscriptions/$subId" "Resource Policy Contributor (learner, policyAssignments/write)"
    Grant-Role $userId $contributorRoleId           "/subscriptions/$subId/resourceGroups/$azdRg" "Contributor (learner, botServices/write)"

    # The service principal calls the Foundry data plane below, so it needs Foundry User too.
    $servicePrincipal = Get-AzADServicePrincipal -ApplicationId $appId -ErrorAction Stop
    if (-not $servicePrincipal) {
        throw "Could not resolve the deployment service principal '$appId'."
    }
    Grant-Role $servicePrincipal.Id $foundryUserRoleId $aiProjectId "Foundry User (service principal)"

    # === Guardrail policy, guardrail agents, traces and evals (not managed by azd) ===
    $armVersion    = "2025-06-01"
    $raiPolicyName = "caldova-enforce"
    $raiPolicy     = Get-Content -Raw -Path (Join-Path $labDir "rai-policy-caldova-enforce.json") | ConvertFrom-Json
    $raiPath       = "$aiResourceId/raiPolicies/$raiPolicyName`?api-version=$armVersion"
    $r = Invoke-AzRestMethod -Method PUT -Path $raiPath -Payload (ConvertTo-Json -InputObject @{ properties = $raiPolicy.properties } -Depth 30 -Compress)
    if ($r.StatusCode -ge 400) { throw "RAI policy PUT returned $($r.StatusCode): $($r.Content)" }

    $projectEndpoint = Get-AzdEnvValue `
        @("FOUNDRY_PROJECT_ENDPOINT", "AZURE_AI_PROJECT_ENDPOINT") `
        "the Foundry project endpoint"
    $projectEndpoint = $projectEndpoint.TrimEnd("/")

    function Invoke-Data([string]$method, [string]$url, $body = $null, [int]$retries = 20) {
        for ($i = 1; ; $i++) {
            try {
                $token = (Get-AzAccessToken -ResourceUrl 'https://ai.azure.com' -ErrorAction Stop).Token
                if ($token -is [securestring]) { $token = (New-Object System.Net.NetworkCredential("", $token)).Password }
                $p = @{ Method = $method; Uri = $url; Headers = @{ Authorization = "Bearer $token" }; ContentType = "application/json" }
                if ($null -ne $body) { $p.Body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 30 -Compress)) }
                return Invoke-RestMethod @p
            } catch {
                $code = 0
                if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
                if ($i -ge $retries -or $code -notin 0, 401, 403, 404, 409, 429, 500, 502, 503) { throw }
                Start-Sleep -Seconds 15
            }
        }
    }

    foreach ($a in $guardrailAgents) {
        $def = $a.definition
        $def.model = $agentModel
        $def.rai_config.rai_policy_name = "$aiResourceId/raiPolicies/$raiPolicyName"
        $created = Invoke-Data "POST" "$projectEndpoint/agents/$($a.name)/versions?api-version=v1" @{ definition = $def; description = $a.description }
        Write-Host "Guardrail agent $($a.name) version $($created.version)"
    }

    $postDeployFailures = New-Object System.Collections.Generic.List[string]
    $traces = Get-Content -Raw -Path (Join-Path $labDir "traces\story-traces.json") | ConvertFrom-Json
    $oai = "$projectEndpoint/openai/v1"
    foreach ($group in ($traces | Group-Object agent)) {
        $name = $group.Name
        try {
            $conv = Invoke-Data "POST" "$oai/conversations" @{ metadata = @{ story = "caldova-recommendation-not-approval"; agent = $name } }
            $turns = foreach ($t in $group.Group) {
                @{ type = "message"; role = "user"; content = $t.prompt }
                @{ type = "message"; role = "assistant"; content = $t.output }
            }
            Invoke-Data "POST" "$oai/conversations/$($conv.id)/items" @{ items = @($turns) } | Out-Null
            Write-Host "Uploaded $($group.Count) traces for $name"
        } catch {
            $failureMessage = "Trace upload failed for ${name}: $($_.Exception.Message)"
            $postDeployFailures.Add($failureMessage)
            Write-Warning $failureMessage
        }
    }

    $sourceRoot = Split-Path -Parent (Split-Path -Parent $labDir)
    $replayCount = 15
    $extra = @()
    $datasetFile = Join-Path $sourceRoot (Join-Path "lab662" "lab662-agent-query-dataset.jsonl")
    if (Test-Path $datasetFile) {
        $extra += Get-Content $datasetFile | Where-Object { $_.Trim() } | ForEach-Object {
            $record = $_ | ConvertFrom-Json
            if ($record.question -notmatch "file search") {
                [pscustomobject]@{ agent = "caldova-$($record.agent)"; prompt = $record.question }
            }
        }
    }
    foreach ($file in Get-ChildItem (Join-Path $sourceRoot "caldova-agent-tests") -Filter *.jsonl -ErrorAction SilentlyContinue) {
        $extra += Get-Content $file.FullName | Where-Object { $_.Trim() } | ForEach-Object {
            $record = $_ | ConvertFrom-Json
            [pscustomobject]@{ agent = "caldova-$($record.agent)"; prompt = $record.query }
        }
    }
    foreach ($group in ($traces | Group-Object agent)) {
        $name = $group.Name
        $pool = @(@($group.Group.prompt) + @($extra | Where-Object { $_.agent -eq $name } | ForEach-Object { $_.prompt }) |
            Where-Object { $_ } | Select-Object -Unique)
        if (-not $pool.Count) { throw "No replay prompts are available for $name." }
        $prompts = for ($promptIndex = 0; $promptIndex -lt $replayCount; $promptIndex++) { $pool[$promptIndex % $pool.Count] }
        Write-Host "Replaying $($prompts.Count) prompts for $name ($($pool.Count) distinct)"
        $completedCount = 0
        $blockedCount = 0
        $failedCount = 0
        $conv = $null
        for ($promptIndex = 0; $promptIndex -lt $prompts.Count; $promptIndex++) {
            try {
                if ($promptIndex % 5 -eq 0 -or -not $conv) {
                    $conv = Invoke-Data "POST" "$oai/conversations" @{ metadata = @{ source = "replay"; agent = $name } }
                }
                $response = Invoke-Data "POST" "$oai/responses" @{
                    conversation = $conv.id
                    input = $prompts[$promptIndex]
                    agent_reference = @{ name = $name; type = "agent_reference" }
                }
                if ($response.status -ne "completed") {
                    throw "Replay response ended with status '$($response.status)'."
                }
                $completedCount++
                Write-Host "  $name [$($promptIndex + 1)/$($prompts.Count)] $($response.status)"
            }
            catch {
                $replayError = $_
                $conv = $null
                $details = $null
                if ($replayError.ErrorDetails.Message) {
                    try { $details = $replayError.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop }
                    catch { $details = $null }
                }
                if ($details.error.code -eq "content_filter" -or $details.error.innererror.code -eq "ContentFiltered") {
                    $blockedCount++
                    Write-Host "  $name [$($promptIndex + 1)/$($prompts.Count)] blocked by content policy"
                    continue
                }
                $failedCount++
                $failureMessage = "Replay failed for ${name} [$($promptIndex + 1)/$($prompts.Count)]: $($replayError.Exception.Message)"
                $postDeployFailures.Add($failureMessage)
                Write-Warning $failureMessage
            }
        }
        Write-Host "Replay summary for ${name}: $completedCount completed, $blockedCount policy-blocked, $failedCount failed."
    }

    foreach ($group in ($traces | Group-Object agent)) {
        $name = $group.Name
        try {
            # azd deploys the agent, so read its current version instead of tracking it from a create call.
            $agentVersion = "$((Invoke-Data 'GET' "$projectEndpoint/agents/${name}?api-version=v1").versions.latest.version)"
            $criteria = foreach ($c in "coherence", "relevance", "task_adherence") {
                @{ type = "azure_ai_evaluator"; name = $c; evaluator_name = "builtin.$c"
                   data_mapping = @{ query = "{{item.query}}"; response = "{{sample.output_text}}" }
                   initialization_parameters = @{ deployment_name = $judgeModel } }
            }
            $ev = Invoke-Data "POST" "$oai/evals" @{
                name = "lab662-$name-story"
                data_source_config = @{ type = "custom"; include_sample_schema = $true
                    item_schema = @{ type = "object"; properties = @{ query = @{ type = "string" }; act = @{ type = "string" } }; required = @("query") } }
                testing_criteria = @($criteria)
            }
            $items = foreach ($t in $group.Group) { @{ item = @{ query = $t.prompt; act = $t.act } } }
            Invoke-Data "POST" "$oai/evals/$($ev.id)/runs" @{
                name = "$name-story-run"
                data_source = @{
                    type = "azure_ai_target_completions"
                    source = @{ type = "file_content"; content = @($items) }
                    input_messages = @{ type = "template"; template = @(@{ type = "message"; role = "user"; content = @{ type = "input_text"; text = "{{item.query}}" } }) }
                    target = @{ type = "azure_ai_agent"; name = $name; version = $agentVersion }
                }
            } | Out-Null
            Write-Host "Started eval for $name"
        } catch {
            $failureMessage = "Eval start failed for ${name}: $($_.Exception.Message)"
            $postDeployFailures.Add($failureMessage)
            Write-Warning $failureMessage
        }
    }

    if ($postDeployFailures.Count) {
        throw "Post-deployment checks failed ($($postDeployFailures.Count)): $($postDeployFailures -join '; ')"
    }

    Write-Host ">>> Lifecycle action complete. Project: $projectEndpoint"
}
catch {
    Write-Host "FATAL: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    throw
}
finally {
    Stop-Transcript
} 