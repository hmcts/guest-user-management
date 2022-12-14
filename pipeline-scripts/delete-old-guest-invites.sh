#!/bin/bash
set -e

branch=$1

min_user_age_days=7
min_user_age_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${min_user_age_days} days ago")

users_file=unaccepted_invites.txt

. pipeline-scripts/delete-user.sh $branch

# Remove guest users in Azure AAD that haven't accepted their invite after 31 days
delete_old_invites() {
  # Create file with users that haven't accepted invite within a week
  az ad user list --query="[?userType=='Guest' && userState=='PendingAcceptance' && createdDateTime<'${min_user_age_date}' ].{DisplayName: displayName, ObjectId:objectId, Mail:mail}" -o json > ${users_file}

  unaccepted_invite_count=$(jq -r .[].ObjectId ${users_file} | wc -l )

  if [[ ${unaccepted_invite_count} -gt 0 ]]; then
    echo "Number of users to be deleted: ${unaccepted_invite_count}"
    while IFS=" " read -r object_id mail display_name
    do

      delete_user "$object_id" "$mail" "$display_name" &
    
    done <<< "$(jq -r '.[] | "\(.ObjectId) \(.Mail) \(.DisplayName)"' ${users_file})"
    wait
  else
    echo "No unaccepted invites found, nothing to do."
  fi
}

if [[ $branch == "master" ]]; then
  echo "Not deleting old guest invites temporarily - see DTSPO-11798"
  #echo "Deleting users that haven't accepted their invite within ${min_user_age_days} days"
  #delete_old_invites
  #echo "Guest users deleted"
else
  echo "Creating list of users that will be deleted when this script runs on the default branch"
  delete_old_invites
fi
