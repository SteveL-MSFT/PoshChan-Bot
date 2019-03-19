param([string] $QueueItem, $TriggerMetadata)

$item = $QueueItem | ConvertFrom-Json

$headers = @{
    Authorization = "token $($env:GITHUB_PERSONAL_ACCESS_TOKEN)"
}

function Push-GitHubComment($message) {
    Push-OutputBinding -Name githubrespond -Value @{ url = $item.commentsUrl; message = $message }
}

Write-Host "Retrieving PR from '$($item.pr)'"
$pr = Invoke-RestMethod -Uri $item.pr -Headers $headers

Write-Host "Retrieving statuses from '$($pr.statuses_url)'"
$statuses = (Invoke-RestMethod -Uri $pr.statuses_url -Headers $headers) | Where-Object {
    $null -ne $_.target_url -and $_.target_url.StartsWith("https://$($item.organization).visualstudio.com")
}

Write-Host "Got $($statuses.Count) statuses returned"
$status = $statuses | Where-Object { $_.context -eq $item.context } | Sort-Object id -Descending | Select-Object -First 1

if ($null -eq $status) {
    $contexts = $statuses | Select-Object context -Unique
    $message = @"
Did not find matching build context: ``$($item.context)``
Allowed contexts:
$contexts
"@
    Write-Error $message
    Push-GitHubComment -message $message
    return
}

if ($status.target_url -match "\?buildId=(?<buildId>\d*)") {
    $buildId = $matches.buildId
}
Write-Host "Found buildId: $buildId"
if ($null -eq $buildId) {
    $message = "Could not find ``buildId`` in '$($status.target_url)'"
    Write-Error $message
    Push-GitHubComment -message $message
    return
}

$cred = [pscredential]::new("empty", (ConvertTo-SecureString -String $env:DEVOPS_ACCESSTOKEN -AsPlainText -Force))

try {
    $url = "https://dev.azure.com/$($item.organziation)/$($item.project)/_apis/build/builds/$($buildId)?api-version=5.0"
    Write-Host "Getting build from: $url"
    $build = Invoke-RestMethod -Uri $url -Authentication Basic -Credential $cred
}
catch {
    $_ | Out-String | Write-Error
}

$params = @{
    Uri = "https://dev.azure.com/$($item.organziation)/$($item.project)/_apis/build/builds?api-version=5.0"
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
    $message = "@$($item.user), started rebuild of ``$($item.context)``"
    Push-GitHubComment -message $message
}
catch {
    $_ | Out-String | Write-Error
}
