param([string] $QueueItem, $TriggerMetadata)

$item = $QueueItem | ConvertFrom-Json

$headers = @{
    Authorization = "token $($env:GITHUB_API_KEY)"
}

$pr = Invoke-RestMethod -Uri $item.pr -Headers $headers

$statuses = Invoke-RestMethod -Uri $pr.statuses_url -Headers $headers
$status = $statuses | Where-Object { $_.context -eq $item.context } | Sort-Object id -Descending | Select-Object -First 1

if ($null -eq $status) {
    $contexts = $statuses | Select-Object context -Unique
    $message = @"
Did not find matching build context: $($item.context)
Allowed contexts:
$contexts
"@
    Write-Error $message
    Push-OutputBinding -Name githubrespond -Value @{ url = $item.commentsUrl; message = $message }
    return
}

$cred = [pscredential]::new("empty", (ConvertTo-SecureString -String $env:DEVOPS_ACCESSTOKEN -AsPlainText -Force))

$params = @{
    Uri = "https://dev.azure.com/powershell/powershell/_apis/build/builds?api-version=5.0"
    Method = "Post"
    Authentication = "Basic"
    Credential = $cred
    Body = @{
        buildNumberRevision = $build.buildNumberRevision++
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
}
