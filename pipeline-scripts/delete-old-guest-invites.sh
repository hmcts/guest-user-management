#!/bin/bash
set -e

month_ago=$(date +%Y-%m-%dT%H:%m:%SZ -d '31 days ago')
week_ago=$(date +%Y-%m-%dT%H:%m:%SZ -d '7 days ago')

. pipeline-scripts/delete-user.sh

# Delete users that haven't logged in within 31 days and are over a week old
delete_inactive_users() {

  # Create file with list of guest users that have accepted their invite
  az rest --method GET --uri "https://graph.microsoft.com/beta/users?\$filter=externalUserState eq 'Accepted' and userType eq 'Guest'&\$select=id,displayName,signInActivity,createdDateTime,mail" > accepted_guests.txt
  
  echo "Number of users to be deleted: $(jq -r '.value[].id' accepted_guests.txt | wc -l)"
  
  while IFS=" " read -r object_id mail display_name
  do
    delete_user "$object_id" "$mail" "$display_name" &

  done <<< "$(jq -r '.value[] | select( .createdDateTime < "'${week_ago}'" and .signInActivity.lastSignInDateTime < "'${month_ago}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${month_ago}'") | "\(.id) \(.mail) \(.displayName)"' accepted_guests.txt)"
  wait
  
}

echo "Deleting users that haven't logged in for 31 days"
delete_inactive_users
echo "Users that haven't logged in for 31 days and are older than a week have been deleted."