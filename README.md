# guest-user-management
A repo that holds scripts and an Azure Devops pipeline to manage the deletion of AAD guest users that are either inactive or haven't accepted their invites after a certain amount of time. 

The pipeline is scheduled to run everyday, but can also be run manually if needed. Any pipeline runs not using the default branch will only provide a list of users that need to be deleted.
