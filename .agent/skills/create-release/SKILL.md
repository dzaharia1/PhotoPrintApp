---
name: create-release
description: Guides the agent through compiling, committing, tagging, and publishing a new release of PhotoPrint.
---

# Creating a New Release

This skill guides the agent through cutting a new release of the PhotoPrint macOS application. Because the application binary (`PhotoPrint.app`) is pre-compiled and tracked in the git repository, a release must be compiled locally and committed before pushing the version tag to trigger the GitHub Actions release workflow.

## Release Process Steps

### 1. Compile the Application Locally
Always ensure the latest code changes are compiled into the checked-in application binary.
```bash
./build.sh
```

### 2. Identify Version and Tags
Check the git status and existing tags to determine what files have changed and what the next semantic version should be.
```bash
git status
git tag -l
```
* The tags follow semantic versioning (e.g., `v0.1.0`, `v0.1.1`, `v0.1.2`).
* Determine the next tag (e.g., `v0.1.3`).

### 3. Stage and Commit Changes
You must commit both the source file modifications (e.g., `ContentView.swift`) and the updated binary (`PhotoPrint.app/Contents/MacOS/PhotoPrint`).
```bash
git add ContentView.swift PhotoPrint.app/Contents/MacOS/PhotoPrint
git commit -m "Release notes or description of changes"
```

### 4. Create the Version Tag
Tag the commit locally with the new version.
```bash
git tag vX.Y.Z
```
*(Replace `vX.Y.Z` with the target version, e.g., `v0.1.3`)*

### 5. Push Branch and Tags
Push the branch and the new tag to the remote repository. Pushing the tag will trigger the automated GitHub Actions release workflow.
```bash
git push origin main
git push origin vX.Y.Z
```

### 6. Automated GitHub Release Workflow
Once pushed, the `.github/workflows/release.yml` workflow will:
1. Compress the tracked `PhotoPrint.app` bundle into `PhotoPrint.zip`.
2. Create a new GitHub Release with the tag name.
3. Attach `PhotoPrint.zip` as a downloadable asset.
