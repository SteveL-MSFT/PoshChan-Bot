$cred = [pscredential]::new("empty", (ConvertTo-SecureString -String $env:DEVOPS_ACCESSTOKEN -AsPlainText -Force))

function Get-DevOpsBuild($Organization, $Project, $BuildId) {
    $url = "https://dev.azure.com/$organization/$project/_apis/build/builds/$($buildId)?api-version=5.0"
    Write-Host "Getting build from: $url"
    Invoke-RestMethod -Uri $url -Authentication Basic -Credential $cred
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

    $null = Invoke-RestMethod @params
}

function Invoke-DevOpsRetry($Organization, $Project, $BuildId) {
    $params = @{
        Uri = "https://dev.azure.com/$organization/$project/_apis/build/builds/$($buildId)?api-version=5.0&retry=true"
        Method = "Patch"
        Authentication = "Basic"
        Credential = $cred
    }

    $null = Invoke-RestMethod @params
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

    $runs = Invoke-RestMethod @params
    $failedRuns = $runs.Value | Where-Object { $_.totalTests -ne $_.passedTests }
    $failedTests = foreach ($failedRun in $failedRuns) {
        $params.Uri = "https://dev.azure.com/$organization/$project/_apis/test/Runs/$($failedRun.id)/results?api-version=5.0&outcomes=failed"
        $params.Method = "Get"
        Invoke-RestMethod @params
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
