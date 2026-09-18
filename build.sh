#!/bin/sh
set -e

echo "#### Generating services in $(pwd) ########"
flutter packages pub run build_runner build --delete-conflicting-outputs
flutter pub run build_runner build