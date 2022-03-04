#!/bin/bash
set -e

month_ago=$(date +%Y-%m-%dT%H:%m:%SZ -d '31 days ago')
week_ago=$(date +%Y-%m-%dT%H:%m:%SZ -d '7 days ago')

delete_user() {
  echo "Deleting user ${3} with the mail address of ${2} and object ID of ${1}"
  # az ad user delete --id 
}

# Remove guest users in Azure AAD that haven't accepted their invite after 31 days
delete_old_invites() {
  # Create file with users that haven't accepted invite within a week
  az ad user list --query="[?userType=='Guest' && userState=='PendingAcceptance' && createdDateTime<'${week_ago}' ].{DisplayName: displayName, ObjectId:objectId, Mail:mail}" -o table > unaccepted_invites.txt

  while IFS=" " read -r display_name object_id mail
  do

    delete_user "$object_id" "$mail" "$display_name" &
  
  done <<< "$(tail -n+3 unaccepted_invites.txt)"
  wait
  
}

# Delete users that haven't logged in within 31 days and are over a week old
delete_users_no_login_31_days() {

  # Create file with list of guest users that have accepted their invite
  az rest --method GET --uri "https://graph.microsoft.com/beta/users?\$filter=externalUserState eq 'Accepted' and userType eq 'Guest'&\$select=id,displayName,signInActivity,createdDateTime,mail" > accepted_guests.txt

  while IFS=" " read -r object_id mail display_name
  do
    delete_user "$object_id" "$mail" "$display_name" &

  done <<< "$(jq -r '.value[] | select( .createdDateTime < "'${week_ago}'" and .signInActivity.lastSignInDateTime < "'${month_ago}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${month_ago}'") | "\(.id) \(.mail) \(.displayName)"' accepted_guests.txt)"
  wait
  
}

echo "Deleting users that haven't accepted their invite within a week"
delete_old_invites
echo "Guest users with unaccepted invites older than a week have been deleted"

echo "Deleting users that haven't logged in for 31 days"
delete_users_no_login_31_days
echo "Users that haven't logged in for 31 days and are older than a week have been deleted."