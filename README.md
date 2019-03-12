# PoshChan-Bot

This Bot is designed for use with GitHub enabling requests of the Bot to perform some specific actions by authorized users.

## Supported Commands

All commands need to be directed to @PoshChan and only allowed by Maintainers of the PowerShell repo.

* `Please rebuild <target>`

  `<target>` can be `windows`,`linux`,`macos`,`static-analysis` or a comma separated list of any combination.
  This will initiate a rebuild of the current PullRequest for the specified target(s).

* `Please remind me in <time> <units>`

  `<time>` is an integer and `<units>` can be `minutes`, `hours`, or `days`.
  This will cause PoshChan to simply respond mentioning you after the duration specified.
  You can use this as a way to retrigger a GitHub notification on a Pull Request you want to check on later because the tests haven't finished running.

## Deploying

This Bot is written as an Azure FunctionApp.  To deploy this, create your own Azure FunctionApp and publish the code
in the `FunctionApp` folder to your Azure FunctionApp.

The Bot relies on a GitHub account to be able to post back comments to a Pull Request or Issue.  Create a custom GitHub
account for the Bot.  Generate a Personal Access Token and store that as an environmental variable called `GITHUB_PERSONAL_ACCESS_TOKEN`
in the `Application Settings` tab as a new `App Setting Name` to keep it secure.

## Register with GitHub

In the `Settings` for your GitHub repository, go to `Webhooks` and add a new webhook that is the URL to your
HTTP bound Azure Function.
