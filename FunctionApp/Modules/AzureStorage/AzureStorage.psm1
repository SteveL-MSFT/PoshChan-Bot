function CreateAuthHeader([string]$canonicalizedString,[string]$storageAccount,[string]$storageKey)
{
    [byte[]] $bytes = [System.Convert]::FromBase64String($storageKey)
    [System.Security.Cryptography.HMACSHA256] $SHA256 = [System.Security.Cryptography.HMACSHA256]::new($bytes)
    [byte[]] $dataToSha256 = [System.Text.Encoding]::UTF8.GetBytes($canonicalizedString)
    $signature = [System.Convert]::ToBase64String($SHA256.ComputeHash($dataToSha256))
    "SharedKeyLite $($storageAccount):$signature"
}

function Push-AzureStorageQueue
{
    param(
        [parameter(Mandatory=$true)]
        [string]$queue,

        [parameter(Mandatory=$true)]
        [string]$storageAccount,

        [parameter(Mandatory=$true)]
        [string]$storageKey,

        [parameter(Mandatory=$true)]
        [object]$object,

        [parameter()]
        [int]$visibilitySeconds = 0
    )

    $json = $object | ConvertTo-Json -Compress
    Write-Verbose "Object = $json"

    $resource = "$queue/messages"
    $storageUrl = "https://$storageAccount.queue.core.windows.net/$resource"

    if ($visibilitySeconds -gt 0) {
        $storageUrl += "?visibilitytimeout=$visibilitySeconds"
    }

    $date = [datetime]::UtcNow.ToString("R", [System.Globalization.CultureInfo]::InvariantCulture)
    [string] $canonicalizedResource = "/$storageAccount/$resource"
    $contentType = "application/x-www-form-urlencoded"
    $version = "2017-04-17"

    [string] $stringToSign = "POST`n`n$contentType`n`nx-ms-date:$date`nx-ms-version:$version`n$canonicalizedResource"
    Write-Verbose $stringToSign
    $headers = @{
        "Accept-Charset" = "UTF-8"
        Authorization = (CreateAuthHeader -canonicalizedString $stringToSign -storageAccount $storageAccount -storageKey $storageKey)
        "Content-Type" = $contentType
        "x-ms-version" = $version
        "x-ms-date" = $date
    }

    $headers | Out-String | Write-Verbose

    $queueMessage = [Text.Encoding]::UTF8.GetBytes($json)
    $queueMessage =[Convert]::ToBase64String($queueMessage)
    $body = "<QueueMessage><MessageText>$queueMessage</MessageText></QueueMessage>"

    $null = Invoke-RestMethod -Uri "$storageUrl" -Headers $headers -Method Post -Body $body -SkipHeaderValidation
}