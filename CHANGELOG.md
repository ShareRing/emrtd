# Changelog

## 0.2.0

- make the npm package public
- push releases to origin main
- add a script to reserve the npm package name
- point install docs at the published packages
- cut release notes from the changelog and mirror it publicly
- replace dist.sh with release.sh that bumps, writes the changelog and tags
- build release frameworks with the latest Xcode 26
- document releasing from the private repo
- add the release workflow for the private repo
- add the public repo's manifests, podspec and README assembly
- build the binding pods static so they can depend on a prebuilt EmrtdCore
- publish a placeholder sources jar instead of the Android source
- ship the iOS Swift layer as a binary framework in release zips
- update MasterList 20261013
- give the android scan sheet a light mode and say device
- let dist.sh bump the version before building
- keep the android scan sheet steady and inert once closing
- document the android scan sheet and progress pattern
- name the file being read on the ios nfc sheet
- show a scan sheet on android like the ios nfc sheet
- wrap the status badges when they do not fit
- document the bridge fixes
- carry error details and the full model to flutter
- carry error kind and debug log to rn
- add read_error_to_json for the bridges
- reject a malformed challenge in rn ios
- report bad options instead of throwing on android bridges
- reject a second concurrent scan on android
- fix install paths and ios setup in readme
- ship a standalone podspec in dist
- document install from dist and full api reference
- add dist script for in-house installs
- document tests and password handling
- add android binding tests
- add ios binding tests
- wipe access key copies after a read
- cover extended length dh pace in sim
- enable extended length apdus on ios
- add fuzz targets and mutation test
- match full name and error codes across demos

