#!/bin/bash
set -e

branch=$1

max_inactive_days=31
min_user_age_days=7

max_inactive_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${max_inactive_days} days ago")
min_user_age_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${min_user_age_days} days ago")

users_file=guests.json

. pipeline-scripts/delete-user.sh $branch

# Delete users that haven't logged in within 31 days and are over a week old
delete_inactive_guests() {

  # Create file with list of guest users that have accepted their invite
  az rest --method GET --uri "https://graph.microsoft.com/beta/users?\$filter=externalUserState eq 'Accepted' and userType eq 'Guest' and createdDateTime le ${min_user_age_date}&\$select=id,displayName,signInActivity,createdDateTime,mail" > ${users_file}
  
  echo "Number of users to be deleted: $(jq -r '.value[] | select(.signInActivity.lastSignInDateTime < "'${max_inactive_date}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${max_inactive_date}'") | .id' ${users_file} | wc -l)"
  
  while IFS=" " read -r object_id mail display_name
  do
    delete_user "$object_id" "$mail" "$display_name" &

  done <<< "$(jq -r '.value[] | select(.signInActivity.lastSignInDateTime < "'${max_inactive_date}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${max_inactive_date}'") | "\(.id) \(.mail) \(.displayName)"' ${users_file})"
  wait
  
}

echo "Deleting users that haven't logged in for 31 days"
delete_inactive_guests
echo "Users that haven't logged in for 31 days and are older than a week have been deleted."