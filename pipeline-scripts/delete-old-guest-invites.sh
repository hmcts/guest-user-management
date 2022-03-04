#!/bin/bash
set -e

month_ago=$(date +%Y-%m-%dT%H:%m:%SZ -d '31 days ago')
week_ago=$(date +%Y-%m-%dT%H:%m:%SZ -d '7 days ago')

. pipeline-scripts/delete-user.sh

# Remove guest users in Azure AAD that haven't accepted their invite after 31 days
delete_old_invites() {
  # Create file with users that haven't accepted invite within a week
  az ad user list --query="[?userType=='Guest' && userState=='PendingAcceptance' && createdDateTime<'${week_ago}' ].{DisplayName: displayName, ObjectId:objectId, Mail:mail}" -o table > unaccepted_invites.txt

  echo "Number of users to be deleted: $(tail -n+3 unaccepted_invites.txt | wc -l)"

  while IFS=" " read -r display_name object_id mail
  do

    delete_user "$object_id" "$mail" "$display_name" &
  
  done <<< "$(tail -n+3 unaccepted_invites.txt)"
  wait
  
}

echo "Deleting users that haven't accepted their invite within a week"
delete_old_invites
echo "Guest users with unaccepted invites older than a week have been deleted"
