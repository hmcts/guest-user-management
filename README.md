# guest-user-management
Scripts and an Azure Devops pipeline to manage the deletion of AAD guest users that are either inactive or haven't accepted their invites after a certain amount of time. 

The pipeline is scheduled to run every day, but can also be run manually if needed. Any pipeline runs not using the default branch will only provide a list of users that need to be deleted.

[Gov Notify](https://www.notifications.service.gov.uk/services/9db77ef0-651a-4bff-b4de-da63f02b247d) is used to send emails to warn users that their accounts are going to be deleted if they don't take any action.

[Documentation for Gov Notify](https://www.notifications.service.gov.uk/documentation) will help get you started, if you would like to understand how it works.
If you have any questions or need access, ask a member of the `Platform Operations` team in the `#platform-operations` Slack channel.

## Running the scripts

If you plan on editing the email template or testing the notifications you will need an API Key 

Get and set the Notify API Key:

```shell
export API_KEY=$(az keyvault secret show -n guest-user-mgmt-notify-api-key --vault dtssharedservicesprodkv --query value)
```

Run the script. Setting the first argument (branch name) to test mean you will only get a plan, it's recommended that you only run plans locally so always set this argument to something other than the default branch.

```shell
./delete-inactive-guest-users.sh test $API_KEY
```