# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)

$item = $QueueItem | ConvertFrom-Json
$url = $item.url
$message = $item.message

if ($null -eq $message) {
    Write-Error "Message is missing"
    return
}

Write-Host "Posting message:`n$message"
Write-Host "To URL: $url"

$message = [System.Web.HttpUtility]::JavaScriptStringEncode($message)

$json = @{
    body = $message
} | ConvertTo-Json -Compress

try {
    $headers = @{
        Authorization = "token $($env:GITHUB_PERSONAL_ACCESS_TOKEN)"
    }

    Invoke-RestMethod -Headers $headers -Uri $url -Method Post -Body $json
} catch {
    $_ | Out-String | Write-Error
}
