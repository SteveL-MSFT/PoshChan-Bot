function Push-Queue($queue, $object, $visibilitySeconds) {
    Push-AzureStorageQueue -queue $queue -storageAccount $env:STORAGE_ACCOUNT -storageKey $env:STORAGE_KEY -object $object -visibilitySeconds $visibilitySeconds
}
