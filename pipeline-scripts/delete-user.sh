#!/bin/bash
set -e

branch=$1

delete_user() {

  if [[ $branch == "master" ]]; then
    echo "Deleting user ${3} with the mail address of ${2} and object ID of ${1}"
    # az ad user update --id ${1} --account-enabled false
    # az ad user delete --id
  else
    echo "Plan: user ${3}, mail address ${2}, object ID ${1}"
  fi
}