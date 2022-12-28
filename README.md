# guest-user-management
Scripts and an Azure Devops pipeline to manage the deletion of AAD guest users that are either inactive or haven't accepted their invites after a certain amount of time. 

The pipeline is scheduled to run every day, but can also be run manually if needed. Any pipeline runs not using the default branch will only provide a list of users that need to be deleted.

[Gov Notify](https://www.notifications.service.gov.uk/services/9db77ef0-651a-4bff-b4de-da63f02b247d) is used to send emails to warn users that their accounts are going to be deleted if they don't take any action.

[Documentation for Gov Notify](https://www.notifications.service.gov.uk/documentation) will help get you started, if you would like to understand how it works.
If you have any questions or need access, ask a member of the `Platform Operations` team in the `#platform-operations` Slack channel.


## Inactive guest users script

The Inactive Guest Users script will delete any users that have been inactive for a certain amount of days, at the time of writing this was 31 days.
Notifications get sent to users on the 7th, 5th, 3rd and last day before getting deleted, so they have enough time to sign back in.

Initially, all users, including those that may just get a notification, are pulled into a file called guests.json and processed. 
The script checks both interactive and non-interactive sign-ins and decides which one was the most recent login, this is then used to determine whether the user is inactive and should be deleted or not.
Due to some inaccuracies when getting all users and querying for the sign in activity, if the user is earmarked for deletion on the first pull of users a second query on their sign in activity is done, this time though only get that specific user.
The script will attempt to get the sign in activity twice and then depending on the value of the most recent log in the script will do a few things

| Most Recent Sign-in Value                                | Description                                                                                  | Action               |
|----------------------------------------------------------|----------------------------------------------------------------------------------------------|----------------------|
| date before the inactive date but after the warning date | User isn't fully inactive but is close.                                                      | Warning notification |
| date after the max inactivity date                       | User is inactive                                                                             | Delete               |
| null                                                     | This is usually an error with the sign-in activity, usually cleared by re-running the script | warning in pipeline  |
| empty                                                    | This means that the user hasn't logged in before and should be deleted.                      | Delete               |


## Running the scripts

If you plan on editing the email template or testing the notifications you will need an API Key 

Get and set the Notify API Key:

```shell
export API_KEY=$(az keyvault secret show -n guest-user-mgmt-notify-api-key --vault dtssharedservicesprodkv --query value)
```

Run the script. Setting the first argument (branch name) to test mean you will only get a plan, it's recommended that you only run plans locally so always set this argument to something other than the default branch.

```shell
./pipeline-scripts/delete-inactive-guest-users.sh test $API_KEY
```