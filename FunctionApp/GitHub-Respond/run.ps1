# Input bindings are passed in via param block.
param($QueueItem, $TriggerMetadata)

$url = $QueueItem.url
$message = $QueueItem.message

if ($null -eq $message) {
    Write-Error "Message is missing"
    return
}

Write-Host "Posting message:`n$message"
Write-Host "To URL: $url"

$json = @{
    body = $message
} | ConvertTo-Json -Compress

try {
    Send-GitHubComment -Url $url -Body $json
} catch {
    $_ | Out-String | Write-Error
}
