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