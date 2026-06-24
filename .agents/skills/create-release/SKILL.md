---
name: create-release
description: Guides the agent through compiling, committing, tagging, and publishing a new release of PhotoPrint.
---

# Creating a New Release

This skill guides the agent through cutting a new release of the PhotoPrint macOS application. Because the application binary (`PhotoPrint.app`) is pre-compiled and tracked in the git repository, a release must be compiled locally and committed before pushing the version tag to trigger the GitHub Actions release workflow.

## Release Process Steps

### 1. Identify Version and Tags
Check the git status and existing tags to determine what files have changed and what the next semantic version should be.
```bash
git status
git tag -l
```
* The tags follow semantic versioning (e.g., `v1.0.11`, `v1.0.12`).
* Determine the next tag (e.g., `v1.0.13`).

### 2. Compile, Sign, and Notarize the Application Locally
Run the release build script with the version number. This compiles the app, updates version strings in `Info.plist`, signs with Developer ID Application, notarizes with Apple Notary Service, staples the ticket, and stages all modified files in git.
```bash
./build-release.sh X.Y.Z
```
*(Replace `X.Y.Z` with the target version, e.g., `1.0.13`)*

### 3. Stage and Commit Changes
If you have any extra non-compiled changes (like code edits in `ContentView.swift`), ensure they are staged, then commit the staged release files:
```bash
git add ContentView.swift
git commit -m "Release vX.Y.Z - Description of changes"
```

### 4. Create the Version Tag
Tag the commit locally with the new version.
```bash
git tag vX.Y.Z
```
*(Replace `vX.Y.Z` with the target version, e.g., `v1.0.13`)*

### 5. Push Branch and Tags
Push the branch and the new tag to the remote repository. Pushing the tag will trigger the automated GitHub Actions release workflow.
```bash
git push origin main
git push origin vX.Y.Z
```

### 6. Automated GitHub Release Workflow
Once pushed, the `.github/workflows/release.yml` workflow will:
1. Compress the tracked and notarized `PhotoPrint.app` bundle into `PhotoPrint.zip` using `ditto`.
2. Create a new GitHub Release with the tag name.
3. Attach `PhotoPrint.zip` as a downloadable asset.

