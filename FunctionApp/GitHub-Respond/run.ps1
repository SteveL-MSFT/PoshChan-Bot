# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)

$item = $QueueItem | ConvertFrom-Json
$url = $item.url
$message = $item.message

if ($null -eq $body) {
    Write-Error "Body is missing"
    return
}

$message
$message = [HttpUtility]::JavaScriptStringEncode($message)

$output = @{
    body = $message
} | ConvertTo-Json -Compress

try {
    $headers = @{
        Authorization = "token $($env:GITHUB_API_KEY)"
    }

    Invoke-RestMethod -Headers $headers -Url $url -Method Post -Body $output
} catch {
    $_ | Out-String | Write-Error
}
