#!/bin/bash
cd "$(dirname "$0")" || exit 1
bash macos/speedtest.sh "$@"
result=$?
printf '\nPress Enter to close / Kapatmak için Enter: '
read -r answer
exit "$result"
