#!/bin/bash
set -e

cd "$(dirname "$0")"

if [[ $(uname) == "Darwin" ]]; then
  shopt -s expand_aliases
  alias date="gdate"
  which date
fi

branch=$1
notify_api_key=$2

pipeline_scheduled_run_time="02:00"

# Number of days before deletion date that a user will start getting notified about being deleted
warn_inactive_days=7

# Number of days a user can be inactive before being deleted
delete_inactive_days=31

# Number of days old that an account has to be before being processed for activity
min_user_age_days=7

max_inactive_days=$(("${delete_inactive_days}" - "${warn_inactive_days}"))
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
  local full_name=
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
  local sign_in_activity
  local last_non_interactive_sign_in_date_time_retry
  local last_sign_in_date_time_retry
  local most_recent_login_date_retry

  sign_in_activity=$(az rest --method get --uri "https://graph.microsoft.com/beta/users/${object_id}?select=signInActivity")

  last_non_interactive_sign_in_date_time_retry=$(jq -r .signInActivity.lastNonInteractiveSignInDateTime <<< "${sign_in_activity}")
  last_sign_in_date_time_retry=$(jq -r .signInActivity.lastSignInDateTime <<< "${sign_in_activity}")

  most_recent_login_date_retry=$(most_recent_login "${last_sign_in_date_time_retry}" "${last_non_interactive_sign_in_date_time_retry}")

  echo "${most_recent_login_date_retry}"
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

  # Set full name of user given_name adn surname will be used if neither are null
  formatted_name=$(set_full_name "${display_name}" "${given_name}" "${surname}")

  last_sign_in_date_time=$(jq -r .signInActivity.lastSignInDateTime <<< "${user}")
  last_non_interactive_sign_in_date_time=$(jq -r .signInActivity.lastNonInteractiveSignInDateTime <<< "${user}")

  most_recent_login_date=$(most_recent_login "${last_sign_in_date_time}" "${last_non_interactive_sign_in_date_time}")

  if [[ "${most_recent_login_date}" == "null" ]] || [[ "${most_recent_login_date}" == "" ]]; then
    # Get user directly and check for most recent sign in
    most_recent_login_date=$(get_user_sign_in_activity "${object_id}")

    if [[ "${most_recent_login_date}" == "null" ]]; then
      printf "Sign in activity is null for user %s with Object ID of %s. Please re-run the pipeline or manually check user.\n" "${formatted_name}" "${object_id}"
      continue
    elif [[ "${most_recent_login_date}" == "" ]]; then
      printf "No sign in activity found for %s\n" "${formatted_name}"
      most_recent_login_date="0001-01-01T00:00:00Z"
    fi

  fi

  days_until_deletion=$(( "${delete_inactive_days}" - (( $(date +%s) - $(date +%s -d "${most_recent_login_date}")) / 86400 + 1) ))

  # If user has been inactive for more than the set amount of days via the var delete_inactive_days
  # get the user specifically and recheck their sign in activity
  if [[ "${days_until_deletion}" -lt "0"  ]]; then

    most_recent_login_date_retry=$(get_user_sign_in_activity "${object_id}")

    if [[ "${most_recent_login_date_retry}" != "null" ]] && [[ "${most_recent_login_date_retry}" > "${most_recent_login_date}"  ]]; then
      most_recent_login_date="${most_recent_login_date_retry}"
      days_until_deletion=$(( "${delete_inactive_days}" - (( $(date +%s) - $(date +%s -d "${most_recent_login_date_retry}")) / 86400 + 1) ))
    elif [[ "${most_recent_login_date_retry}" == "null" ]]; then
      printf "Sign in activity is null for user %s with Object ID of %s. Please re-run the pipeline or manually check user.\n" "${formatted_name}" "${object_id}"
      continue

    fi
  fi
  # Delete user if sign in activity suggests that the user hasn't signed in
  if [[ "${days_until_deletion}" -lt "0"  ]]; then

    if [[ "${branch}" =~ ^(main|master)$ ]]; then
      if [[ "${most_recent_login_date}" == "0001-01-01T00:00:00Z" ]]; then
        printf "Deleting user %s as it looks like the user hasn't logged in and their account is older than %s days\n" "${formatted_name}" "${min_user_age_days}"
      else
        printf "Deleting user %s as the last login recorded was %s and that is more than %s days ago\n" "${formatted_name}" "${most_recent_login_date}"  "${delete_inactive_days}"
      fi

      # Delete user
#      az rest --method DELETE --uri "https://graph.microsoft.com/v1.0/users/${1}"
    else
      if [[ "${most_recent_login_date}" == "0001-01-01T00:00:00Z" ]]; then
        printf "Deleting user %s as it looks like the user hasn't logged in and their account is older than %s days\n" "${formatted_name}" "${min_user_age_days}"
      else
        printf "Plan: User %s will be deleted as the last login recorded was %s and that's more than %s days ago\n" "${formatted_name}" "${most_recent_login_date}"  "${delete_inactive_days}"
      fi
    fi
  elif [[ "${days_until_deletion}" -lt "8"  ]]; then

    # Set log in by date
    log_in_by_date=$(date "+%d-%m-%Y ${pipeline_scheduled_run_time}" -d "${most_recent_login_date} + ${delete_inactive_days} days")

    # Check email isn't null
    if [[ "${mail}" == "null" ]]; then
      printf "No email address found for user %s. PLease re-run the pipeline or check the user manually\n" "${formatted_name}"
      continue
    fi

    if [[ "${branch}" =~ ^(main|master)$ ]]; then
      printf "Sending warning notification %s: last_login=%s, days_until_deletion=%s, log_in_by_date=%s\n" "${formatted_name}" "${most_recent_login_date}" "${days_until_deletion}" "${log_in_by_date}"

      # Send warning notification
      node sendMail.js "${mail}" "${formatted_name}" "${notify_api_key}" "${days_until_deletion}" "${delete_inactive_days}" "${log_in_by_date}"
    else
      printf "Plan: Warning notification will be sent to %s when this pipeline runs on the default branch: last_login=%s, days_until_deletion=%s, log_in_by_date=%s\n" "${formatted_name}" "${most_recent_login_date}" "${days_until_deletion}" "${log_in_by_date}"
    fi
  fi

  # Leaving this here to mitigate issues with request limits and throttling
  sleep 3
done