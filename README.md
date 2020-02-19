# PoshChan-Bot

This Bot is designed for use with GitHub enabling requests of the Bot to perform some specific actions by authorized users.

## Architecture

```text
[GitHub WebHook]
        |
        ⚡
        |
        V
<AzF:PoshChan-Bot> -💾-> (AzQ: azdevops-rebuild) -⚡-> <AzF:AzDevOps-Rebuild> -⚡-> [AzDevOps]
        |                                                        |
       💾                                                       💾
        |                                                        |
        V                                                        |
(AzQ: github-respond) <------------------------------------------+
        |
        ⚡
        |
        V
<AzF:GitHub-Respond> -⚡-> [GitHub]
```

1. Request comes in as a GitHub web-hook HTTP request
1. PoshChan-Bot function is instantiated and determines the type of command
    1. If reminder, PoshChan-Bot puts a message in the `github-respond` queue that is hidden for the requested amount of time
    1. if azdevops, PoshChan-Bot puts a message in the `azdevops-rebuild` queue
1. Items in the `github-respond` queue triggers the `GitHub-Respond` function to post to a specific issue a comment
1. Items in the `azdevops-rebuild` queue triggers the `AzDevOps-Rebuild` function
    1. The `AzDevOps-Rebuild` function determines if the request is to rebuild or retry a pull request
    1. A rebuild results in posting to queue a new build for existing pull request
    1. A retry results in patching an existing build for retry

## Supported Commands

All commands need to be directed to @PoshChan and only allowed by authorized users of a repository.
Recommendation is to only allow maintainers and key contributors.

* `Retry <target>`

  `<target>` can be `windows`,`linux`,`macos`,`static-analysis` or a comma separated list of any combination.
  You can also specify `all` if you want everything rebuilt.
  This will initiate a retry of the current PullRequest for the specified target(s).
  A retry differs from a rebuild in that it retries the failed tasks in a pipeline rather than re-executing
  the pipeline entirely.

* `<rebuild|rerun> <target>`

  The verb can be `rebuild` or `rerun`.
  `<target>` can be `windows`,`linux`,`macos`,`static-analysis` or a comma separated list of any combination.
  You can also specify `all` if you want everything rebuilt.
  This will initiate a rebuild of the current PullRequest for the specified target(s).
  A rebuild differs from a retry in that the pipeline is re-executed entirely even if some tasks succeeded.
  Recommendation is to use retry first.

* `Remind me in <time> <units>`

  `<time>` is an integer and `<units>` can be `minutes`, `hours`, or `days`.
  This will cause PoshChan to simply respond mentioning you after the duration specified.
  You can use this as a way to re-trigger a GitHub notification on a Pull Request you want to check on later because the tests haven't finished running.

* `Get test failures`

  The word `test` is optional.
  This will go out to the CI runs and retrieve (up to 5) test failures and post them as a comment in the Pull Request.
  This capability only works if the test results are published to AzDevOps as it does not do any
  log parsing of the CI run and solely relies on published test results.

  If the `failures` feature is enabled in `settings.json`, the same committer who is authorized will
  automatically have test failures posted in their Pull Request as well.

## Deploying

This Bot is written in PowerShell as an Azure FunctionApp (requires Azure Functions v2).
To deploy this, create your own Azure FunctionApp and publish the code in the `FunctionApp` folder to your Azure FunctionApp.

The Bot relies on a GitHub account to be able to post back comments to a Pull Request or Issue.  Create a custom GitHub
account for the Bot.  Generate a Personal Access Token and store that as an environmental variable called `GITHUB_PERSONAL_ACCESS_TOKEN`
in the `Application Settings` tab as a new `App Setting Name` to keep it secure.

## Register with GitHub

In the `Settings` for your GitHub repository, go to `Webhooks` and add a new webhook that is the URL to your
HTTP bound Azure Function.

For the `AzDevOps`, `Reminders`, and requesting `failures` capabilities, the `Issue Comments` event must be enabled for the webhook.
For the `failures` capability to automatically post test failures for a Pull Request, the
`Statuses` event must be enabled for the webhook.

## Configuration

A configuration file called `settings.json` should be in the `.poshchan` folder in the root of the repository.

The format for this file should be:

```json
{
  "version": "0.1",
  "azdevops": {
    "organization": "yourOrganization",
    "project": "yourProject",
    "build_targets": {
      "linux": "Project_CI_Linux",
      "macos": "Project_CI_macOS",
      "windows": "Project_CI_windows",
      "all": [
        "Project_CI_Linux",
        "Project_CI_macOS",
        "Project_CI_windows"
      ]
    },
    "authorized_users": [
      "User1",
      "User2"
    ]
  },
  "failures": {
    "authorized_users": [
      "User1",
      "User2"
    ]
  },
  "reminders": {
    "authorized_users": "*"
  }
}
```

Where `build_targets` map to the associated build names in AzDevOpsPipelines.
`authorized_users` are GitHub usernames authorized to make requests to PoshChan-Bot.

## Testing

Before deploying a new version of PoshChan to production, recommendation is to
create another FunctionApp called PoshChan-Staging and publish to that first.
Create an alternate GitHub account so that the two are independent.
For the staging account, be sure the webhook specifies its alternate name:

```url
https://poshchan-bot-staging.azurewebsites.net/api/poshchan-bot?code=...&name=PoshChan-Staging
```

In this example, the staging bot will only respond to commands sent to `PoshChan-Staging` as
specified by the name given in the webhook.

You can also specify the `DebugTrace` parameter in the URL to get additional tracing
sent to Application Insights:

```url
https://poshchan-bot-staging.azurewebsites.net/api/poshchan-bot?code=...&name=PoshChan-Staging&debugtrace=1
```
