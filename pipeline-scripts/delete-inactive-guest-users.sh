#!/bin/bash
set -e

branch=$1

max_inactive_days=31
min_user_age_days=7

max_inactive_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${max_inactive_days} days ago")
min_user_age_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${min_user_age_days} days ago")

users_file=guests.json

. pipeline-scripts/delete-user.sh $branch

# Delete users that haven't logged in within set number of days and are over a week old
delete_inactive_guests() {

  # Create file with list of guest users that have accepted their invite
  az rest --method GET --uri "https://graph.microsoft.com/beta/users?\$filter=externalUserState eq 'Accepted' and userType eq 'Guest' and createdDateTime le ${min_user_age_date}&\$select=id,displayName,signInActivity,createdDateTime,mail" > ${users_file}
  
  inactive_users_count=$(jq -r '.value[] | select(.signInActivity.lastSignInDateTime < "'${max_inactive_date}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${max_inactive_date}'") | .id' ${users_file} | wc -l)
  
  
  if [[ ${inactive_users_count} -gt 0 ]]; then
    echo "Number of users to be deleted: ${inactive_users_count}"
  
    while IFS=" " read -r object_id mail display_name
    do
      delete_user "$object_id" "$mail" "$display_name" &

    done <<< "$(jq -r '.value[] | select(.signInActivity.lastSignInDateTime < "'${max_inactive_date}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${max_inactive_date}'") | "\(.id) \(.mail) \(.displayName)"' ${users_file})"
    wait
  else
    echo "No inactive users found, nothing to do"
  fi
}


if [[ $branch == "master" ]]; then
  echo "Deleting users that haven't logged in for ${max_inactive_days} days"
  delete_inactive_guests
  echo "Users deleted"
else
  echo "Creating list of user that will be deleted when this script runs on the default branch"
  delete_inactive_guests
fi
