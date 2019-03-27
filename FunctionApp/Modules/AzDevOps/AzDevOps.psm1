$cred = [pscredential]::new("empty", (ConvertTo-SecureString -String $env:DEVOPS_ACCESSTOKEN -AsPlainText -Force))

function Get-DevOpsBuild($Organization, $Project, $BuildId) {
    $url = "https://dev.azure.com/$organization/$project/_apis/build/builds/$($buildId)?api-version=5.0"
    Write-Host "Getting build from: $url"
    try {
        Invoke-RestMethod -Uri $url -Authentication Basic -Credential $cred
    }
    catch {
        $_ | Out-String | Write-Error
        throw $_
    }
}

function Invoke-DevOpsRebuild($Organization, $Project, $Build) {
    $params = @{
        Uri = "https://dev.azure.com/$organization/$project/_apis/build/builds?api-version=5.0"
        Method = "Post"
        Authentication = "Basic"
        Credential = $cred
        Body = @{
            buildNumberRevision = [int]($build.buildNumberRevision) + 1
            id = $build.id
            definition = $build.definition
            sourceVersion = $build.sourceVersion
            sourceBranch = $build.sourceBranch
            buildNumber = $build.buildNumber
            parameters = $build.parameters
            triggerInfo = $build.triggerInfo
        } | ConvertTo-Json
        ContentType = "application/json"
    }

    try {
        $null = Invoke-RestMethod @params
    }
    catch {
        $_ | Out-String | Write-Error
        throw $_
    }
}

function Invoke-DevOpsRetry($Organization, $Project, $BuildId) {
    $params = @{
        Uri = "https://dev.azure.com/$organization/$project/_apis/build/builds/$($buildId)?api-version=5.0&retry=true"
        Method = "Patch"
        Authentication = "Basic"
        Credential = $cred
    }

    try {
        $null = Invoke-RestMethod @params
    }
    catch {
        $_ | Out-String | Write-Error
        throw $_
    }
}

function Get-DevOpsTestFailures($Organization, $Project, $BuildUri) {
    if ($null -ne $env:BUILD_BUILDURI) {
        $buildUri = $env:BUILD_BUILDURI
        $buildId = $env:BUILD_BUILDID
    }
    else {
        $buildId = Split-Path $buildUri -Leaf
    }

    $params = @{
        Uri = "https://dev.azure.com/$organization/$project/_apis/test/runs?api-version=5.0&buildUri=$([uri]::EscapeDataString($buildUri))&includeRunDetails=true"
        Authentication = "Basic"
        Credential = $cred
    }

    try {
        Write-Host "Getting results from: $($params.uri)"
        $runs = Invoke-RestMethod @params
    }
    catch {
        $_ | Out-String | Write-Error
        throw $_
    }

    $failedRuns = $runs.Value | Where-Object { $_.totalTests -ne $_.passedTests }
    $failedTests = foreach ($failedRun in $failedRuns) {
        $params.Uri = "https://dev.azure.com/$organization/$project/_apis/test/Runs/$($failedRun.id)/results?api-version=5.0&outcomes=failed"
        $params.Method = "Get"
        try {
            Invoke-RestMethod @params
        }
        catch {
            $_ | Out-String | Write-Error
            throw $_
        }
    }
    $failedTests.Value | Sort-Object completedDate -Descending | Sort-Object id -Unique | Select-Object testCaseTitle, errorMessage, stackTrace
}

function Get-DevOpsOrgAndProject($Settings, $DefaultOrganization, $DefaultProject) {
    if ($null -ne $settings.azdevops -and $null -ne $settings.azdevops.organization) {
        $organization = $settings.azdevops.organization
    }
    else {
        $organization = $DefaultOrganization
    }

    if ($null -ne $settings.azdevops -and $null -ne $settings.azdevops.project) {
        $project = $settings.azdevops.project
    }
    else {
        $project = $DefaultProject
    }
    $organization, $project
}

function Get-DevOpsTestFailuresMessage($User, $Organization, $Project, $BuildId) {
    $build = Get-DevOpsBuild -Organization $Organization -Project $Project -BuildId $buildId
    $failures = Get-DevOpsTestFailures -Organization $Organization -Project $Project -BuildUri $build.uri
    $sb = [System.Text.StringBuilder]::new()
    $count = $failures.Count
    if ($count -eq 0) {
        return
    }

    $null = $sb.Append("@$user, your last commit had ")
    if ($count -gt 0) {
        $null = $sb.Append("$count ")
    }
    $null = $sb.Append("failures in ``$($build.definition.name)```n")

    if ($count -gt 10) {
        $null = $sb.Append("(These are 10 of the failures)")
        $count = 10
    }

    for ($i = 0; $i -lt $count; $i++) {
        $null = $sb.Append("### $($failures[$i].testcaseTitle)`n")
        $null = $sb.Append("  Error: $($failures[$i].errorMessage)`n")
        $null = $sb.Append("``````stacktrace`n")
        $null = $sb.Append($failures[$i].stacktrace)
        $null = $sb.Append("`n```````n")
    }

    $sb.Replace("`n","`r`n").ToString()
}