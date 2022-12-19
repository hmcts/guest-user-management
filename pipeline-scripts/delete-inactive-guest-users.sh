#!/bin/bash
set -e

cd "$(dirname "$0")"

branch=$1
API_KEY=$2
# Number of days before deletion date that a user will start getting notified about being deleted
warn_inactive_days=7

# Number of days a user can be inactive before being deleted
delete_inactive_days=31

min_user_age_days=7
max_inactive_days=$(("${delete_inactive_days}" - "${warn_inactive_days}" ))
max_inactive_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${max_inactive_days} days ago")
delete_inactive_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${delete_inactive_days} days ago")

min_user_age_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${min_user_age_days} days ago")

echo "warning_date=${max_inactive_date}"
echo "delete_inactive_date=${delete_inactive_date}"
echo "min_user_age_date=${min_user_age_date}"

users_file=guests.json

. delete-user.sh "${branch}"


most_recent_login() {
  local most_recent_login_date

  # Take both login times check which one is the most recent and work with that
  if [[ $1 == "null" ]] && [[ $2 == "null" ]]; then
    most_recent_login_date="null"
  elif [[ $1 == "null" ]]; then
    most_recent_login_date=$2
  elif [[ $2 == "null" ]]; then
    most_recent_login_date=$1
  else
    most_recent_login_date=$([[ "$1" > "$2" ]] && echo "$1" || echo "$2")
  fi

  echo "${most_recent_login_date}"
}

set_full_name() {
    local display_name=$1
    local given_name=$2
    local surname=$3
    local full_name
    # Use display name if given and surname aren't set
    if [[ ${given_name} == "null" ]] || [[ ${surname} == "null" ]]; then
      given_name=$(echo "$display_name" | cut -d "," -f2 )
      surname=$(echo "$display_name" | cut -d "," -f1)
      # Remove the leading whitespace from given name
      full_name=$(printf "%s %s" "${given_name## }" "$surname")
    else
      full_name=$(printf "%s %s" "$given_name" "$surname")
    fi

    echo "${full_name}"
}

get_user_sign_in_activity() {
  local object_id=$1
  local sign_in_activity
  local last_non_interactive_sign_in_date_time
  local last_sign_in_date_time
  local most_recent_login_date

  sign_in_activity=$(az rest --method get --uri "https://graph.microsoft.com/beta/users/${object_id}?select=signInActivity")

  last_non_interactive_sign_in_date_time=$(jq -r .signInActivity.lastNonInteractiveSignInDateTime <<< "${sign_in_activity}")
  last_sign_in_date_time=$(jq -r .signInActivity.lastSignInDateTime <<< "${sign_in_activity}")

  most_recent_login_date=$(most_recent_login "${last_sign_in_date_time}" "${last_non_interactive_sign_in_date_time}")

  echo "${most_recent_login_date}"
}

# Delete users that haven't logged in within set number of days and are over a week old


# Create file with list of guest users that have accepted their invite
NEXT_LINK=
counter=0

until [[ "${NEXT_LINK}" == "null" ]]; do

  if [[ ${counter} == 0 ]]; then
    az rest --method get --uri "https://graph.microsoft.com/beta/users?top=100&filter=externalUserState eq 'Accepted' and createdDateTime le ${min_user_age_date}&select=id,signInActivity,createdDateTime,mail,givenName,surname,displayName" > users-${counter}.json
  else
    az rest --method get --uri "${NEXT_LINK}" > users-${counter}.json
  fi

  NEXT_LINK=$(jq -r '."@odata.nextLink"' users-${counter}.json)

  counter=$(( counter + 1 ))

done

jq -s 'map(.value[])' users-?.json > ${users_file}


inactive_users_count=$(jq -r '.[] | select(.signInActivity.lastSignInDateTime < "'${max_inactive_date}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${max_inactive_date}'") | .id' ${users_file} | wc -l )

if [[ "${inactive_users_count}" == 0 ]]; then
  echo "No inactive users found"
  exit 0
fi

# Loop through inactive users
jq -c '.[] | select(.signInActivity.lastSignInDateTime < "'${max_inactive_date}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${max_inactive_date}'")' ${users_file} | while read -r user; do

  object_id=$(jq -r ".id" <<< "${user}")
  display_name=$(jq -r ".displayName" <<< "${user}")
  given_name=$(jq -r ".givenName" <<< "${user}")
  surname=$(jq -r ".surname" <<< "${user}")
  mail=$(jq -r ".mail" <<< "${user}")

  # Check email isn't null
  if [[ "${mail}" == "null" ]]; then
    printf "No email address found for user %s\n" "${formatted_name}"
    continue
  fi

  # Set full name of user given_name adn surname will be used if neither are null
  formatted_name=$(set_full_name "${display_name}" "${given_name}" "${surname}")

  last_sign_in_date_time=$(jq -r .signInActivity.lastNonInteractiveSignInDateTime <<< "${user}")
  last_non_interactive_sign_in_date_time=$(jq -r .signInActivity.lastSignInDateTime <<< "${user}")

  most_recent_login_date=$(most_recent_login "${last_sign_in_date_time}" "${last_non_interactive_sign_in_date_time}")

  if [[ "${most_recent_login_date}" == "null" ]] || [[ "${most_recent_login_date}" == "" ]]; then
    # Get user directly and check for most recent sign in
    most_recent_login_date=$(get_user_sign_in_activity "${object_id}")

    if [[ "${most_recent_login_date}" == "null" ]]; then
      printf "No log in activity found for %s\n" "${full_name}"
      continue
    fi
  fi

  days_until_deletion=$(( "${delete_inactive_days}" - (( $(date +%s) - $(date +%s -d "${most_recent_login_date}")) / 86400 + 1) ))

  if [[ "${days_until_deletion}" -lt "0"  ]]; then
    printf "Deleting user %s as the last login recorded was %s and that is more than %s days ago\n" "${formatted_name}" "${most_recent_login_date}"  "${delete_inactive_days}"
  else
    printf "Sending warning notification %s: last_login=%s, days_until_deletion=%s, delete_inactive_date=%s\n" "${formatted_name}" "${most_recent_login_date}" "${days_until_deletion}" "${delete_inactive_date}"
    node sendMail.js "${mail}" "${formatted_name}" "${API_KEY}" "${days_until_deletion}" "${delete_inactive_days}"
  fi

done
