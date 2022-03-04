#!/bin/bash
set -e

month_ago=$(date +%Y-%m-%dT%H:%m:%SZ -d '31 days ago')
week_ago=$(date +%Y-%m-%dT%H:%m:%SZ -d '7 days ago')

users_file=unaccepted_invites.txt

. pipeline-scripts/delete-user.sh

# Remove guest users in Azure AAD that haven't accepted their invite after 31 days
delete_old_invites() {
  # Create file with users that haven't accepted invite within a week
  az ad user list --query="[?userType=='Guest' && userState=='PendingAcceptance' && createdDateTime<'${week_ago}' ].{DisplayName: displayName, ObjectId:objectId, Mail:mail}" -o json > ${users_file}


  echo "Number of users to be deleted: $(jq -r .[].ObjectId ${users_file} | wc -l )"

  while IFS=" " read -r object_id mail display_name
  do

    delete_user "$object_id" "$mail" "$display_name" &
  
  done <<< "$(jq -r '.[] | "\(.ObjectId) \(.Mail) \(.DisplayName)"' ${users_file})"
  wait
  
}

echo "Deleting users that haven't accepted their invite within a week"
delete_old_invites
echo "Guest users with unaccepted invites older than a week have been deleted"
