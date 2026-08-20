#!/bin/zsh
# Xcode Cloud runs this automatically right after cloning the repo, before
# any build/archive step. SmartTrainer.xcodeproj is intentionally not
# committed to git (see project.yml) — it's generated from project.yml by
# XcodeGen, so we install XcodeGen and generate it here.
set -e

echo "Installing XcodeGen..."
brew install xcodegen

echo "Generating Xcode project from project.yml..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
