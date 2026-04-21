## 1. Persistence and selection model

- [x] 1.1 Replace the single persisted configuration model with a collection of saved connections plus selected connection ID
- [x] 1.2 Add legacy-state migration so existing single-config users are upgraded into the new multi-config model automatically
- [x] 1.3 Update app view model and storage services to load, save, select, add, and remove saved connections

## 2. Runtime and connection behavior

- [x] 2.1 Update connect logic to use the currently selected saved connection when generating Xray config
- [x] 2.2 Ensure disconnect, quit cleanup, and proxy teardown continue to work with the selected connection model
- [x] 2.3 Define and implement safe behavior for selection changes while connected

## 3. Menu bar and settings UI

- [x] 3.1 Replace direct link editing in the menu bar with saved-connection selection and a Settings action
- [x] 3.2 Add a dedicated settings window scene to the app
- [x] 3.3 Implement the Connections settings tab with list, add, select, and remove actions for saved configs

## 4. Validation and verification

- [x] 4.1 Verify VLESS and Trojan add/remove/select flows work across app relaunches
- [x] 4.2 Verify switching selected configs and connecting uses the expected server configuration
- [x] 4.3 Build the app with `xcodebuild -project teleport.xcodeproj -scheme teleport -configuration Debug build`
