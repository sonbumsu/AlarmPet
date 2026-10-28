#!/bin/bash
# Runs the tests in Tests/ against the app's non-UI code. No Xcode needed.
#   ./test.sh
set -euo pipefail
cd "$(dirname "$0")"

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

SOURCES=(
  NotiPet/Settings/PetReminder.swift
  NotiPet/Settings/PetsStore.swift
  NotiPet/Settings/AppSettings.swift
  NotiPet/Settings/NotificationSettings.swift
  NotiPet/Speech/PetMessage.swift
  NotiPet/Speech/MediaLink.swift
  NotiPet/Speech/PetSound.swift
  NotiPet/Speech/AlarmSound.swift
  NotiPet/Speech/CustomSounds.swift
  NotiPet/Sources/NotificationSource.swift
  NotiPet/Sources/LocalServerSource.swift
  NotiPet/Utilities/AppDirectory.swift
  NotiPet/Utilities/AlarmCatArt.swift
  NotiPet/Utilities/PlaceholderAnimation.swift
  NotiPet/Playback/FrameSequence.swift
)

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macosx14.0" \
  "${SOURCES[@]}" Tests/*.swift -o "$OUT/NotiPetTests"
"$OUT/NotiPetTests"
