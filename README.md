# JoyKeyMapper

A macOS application to map Nintendo Switch Joy-Con and Pro Controller inputs to keyboard and mouse events.

## Prerequisites

- macOS 12.0 or later
- Xcode 14+ and Command Line Tools
- A Nintendo Switch Pro Controller or Joy-Cons

## Installation

### 1. Build the Application

From the project root, run the following command to build the app without requiring a development certificate:

```bash
xcodebuild -workspace JoyKeyMapper.xcworkspace \
           -scheme JoyKeyMapper \
           -configuration Debug build \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO \
           -derivedDataPath build
```

### 2. Move to a Stable Location

MacOS security (TCC) identifies apps by their path and signature. To avoid losing permissions every time you rebuild or move the file, move the built app to your `/Applications` folder:

```bash
cp -R build/Build/Products/Debug/JoyKeyMapper.app /Applications/
```

## Solving "Accessibility Hell"

If the app is enabled in **System Settings > Privacy & Security > Accessibility** but buttons still don't work, or if you get repeated prompts, follow these steps to force-refresh the permissions:

### 1. Force Reset Accessibility Permissions
Open Terminal and run:
```bash
sudo tccutil reset Accessibility jp.0spec.JoyKeyMapper
```

### 2. Register the App with Launch Services
Run this to tell macOS the app is trusted and located in /Applications:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/JoyKeyMapper.app
```

### 3. Re-enable in System Settings
1. Open **System Settings > Privacy & Security > Accessibility**.
2. If `JoyKeyMapper` is in the list, remove it with the `-` button.
3. Click the `+` button and select `/Applications/JoyKeyMapper.app`.
4. Ensure the toggle is **ON**.

## Usage

1. Launch `JoyKeyMapper` from `/Applications`.
2. Grant **Bluetooth** permissions when prompted (required to talk to the controllers).
3. Connect your controller via Bluetooth.
4. Use the menu bar icon to:
   - Configure button mappings.
   - Switch profiles.
   - **Refresh Controllers**: Use this if the controller disconnects and doesn't recover automatically.

## Troubleshooting

- **Logs**: The app writes detailed debug information to `~/JoyKeyMapper.log`. You can watch it in real-time with:
  ```bash
  tail -f ~/JoyKeyMapper.log
  ```
- **Controller Detection**: If other apps (like a web browser) can't see the controller, try disabling your mappings or closing JoyKeyMapper, as it seizes the device for exclusive remapping.
- **Buttons Not Clicking**: Ensure the Accessibility permission is fresh (follow the "Accessibility Hell" steps above).
