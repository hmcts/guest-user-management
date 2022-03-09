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


  echo "Number of users to be deleted: $(jq -r .[].ObjectId ${users_file} | wc -l )"

  while IFS=" " read -r object_id mail display_name
  do

    delete_user "$object_id" "$mail" "$display_name" &
  
  done <<< "$(jq -r '.[] | "\(.ObjectId) \(.Mail) \(.DisplayName)"' ${users_file})"
  wait
  
}

if [[ $branch == "master" ]]; then
  echo "Deleting users that haven't accepted their invite within ${min_user_age_days} days"
  delete_old_invites
  echo "Guest users deleted"
else
  echo "Creating list of users that will be deleted when this script runs on the default branch"
  delete_old_invites
fi