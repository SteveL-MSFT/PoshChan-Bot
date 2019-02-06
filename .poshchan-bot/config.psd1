@{
    BotName = "PoshChan"
    AuthorizedUsers = @("SteveL-MSFT")
    Commands = @(
        @{
            Description = "Run feature tests on PR"
            Pattern = "Please run feature tests"
            WebHook = "..."
            Method= "Post"
            Body = @{
                PullRequest = "<body.issue.pull_request.url>"
            }
        }
        @{
            Description = "Retry build"
            Pattern = "Please retry (?<os>.*?)"
            WebHook = "https://poshchan-bot.azurewebsites.net/api/azdevops"
            Method = "Post"
            Body = @{
                OS = "<matches.os>"
            }
        }
    )
}