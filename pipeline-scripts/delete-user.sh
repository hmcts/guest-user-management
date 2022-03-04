#!/bin/bash
set -e

delete_user() {
  echo "Deleting user ${3} with the mail address of ${2} and object ID of ${1}"
  # az ad user delete --id 
}