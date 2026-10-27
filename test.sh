#!/bin/bash
# Runs the tests in Tests/ against the app's non-UI code. No Xcode needed.
#   ./test.sh
set -euo pipefail
cd "$(dirname "$0")"

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

SOURCES=(
  AlarmPet/Settings/PetReminder.swift
  AlarmPet/Settings/PetsStore.swift
  AlarmPet/Settings/AppSettings.swift
  AlarmPet/Settings/NotificationSettings.swift
  AlarmPet/Speech/PetMessage.swift
  AlarmPet/Speech/PetSound.swift
  AlarmPet/Speech/AlarmSound.swift
  AlarmPet/Sources/NotificationSource.swift
  AlarmPet/Sources/LocalServerSource.swift
  AlarmPet/Utilities/AppDirectory.swift
  AlarmPet/Utilities/AlarmCatArt.swift
  AlarmPet/Utilities/PlaceholderAnimation.swift
  AlarmPet/Playback/FrameSequence.swift
)

swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macosx14.0" \
  "${SOURCES[@]}" Tests/*.swift -o "$OUT/AlarmPetTests"
"$OUT/AlarmPetTests"
