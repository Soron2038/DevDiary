# DevDiary

**Automatic daily development diary for macOS**

DevDiary is a native macOS menubar app that automatically tracks your daily development work based on Git activity and creates readable summaries.

![DevDiary Screenshot](Assets/screenshot.png)

## Features

- 🕐 **Automatic Time Tracking** - Sessions are detected based on Git commit activity
- 📝 **Git-based Activity** - Tracks commits, additions, deletions across all your repositories
- 🔒 **100% Local & Private** - All data stays on your Mac, no cloud, no telemetry
- 🌍 **Localized** - Available in English and German
- 📊 **Daily Statistics** - See your work time, commits, and code changes at a glance

## Installation

### Download

Download the latest release from [GitHub Releases](https://github.com/Soron2038/DevDiary/releases).

### First Launch

Since the app is not signed with an Apple Developer certificate, macOS will show a security warning.

**To open the app:**
1. Right-click (or Control-click) on `DevDiary.app`
2. Select "Open" from the context menu
3. Click "Open" in the dialog

Or:
1. Try to open the app normally
2. Go to **System Settings → Privacy & Security**
3. Click "Open Anyway" next to the DevDiary warning

After the first launch, the app will open normally.

## Usage

1. **First Launch**: The onboarding wizard will help you set up DevDiary and discover your Git repositories
2. **Menubar Icon**: Click the DevDiary icon in your menubar to see today's summary
3. **Dashboard**: Click "Dashboard" to see detailed statistics, history, and manage projects
4. **Settings**: Configure polling interval, session timeout, and data retention

### Tracked Folders

DevDiary automatically searches for Git repositories in:
- `~/Developer`
- `~/Projects`
- `~/Code`
- `~/Documents`

You can manually add additional repositories in the Projects view.

## Requirements

- macOS 13.0 (Ventura) or later
- Git installed on your system

## Building from Source

```bash
# Clone the repository
git clone https://github.com/Soron2038/DevDiary.git
cd DevDiary

# Build debug version
swift build

# Run
swift run DevDiary

# Build release and create DMG
./scripts/build-release.sh
```

## Privacy

DevDiary is designed with privacy as a core principle:

- **Local Only**: All data is stored locally in `~/Library/Application Support/DevDiary/`
- **No Network**: The app never connects to the internet
- **No Telemetry**: No usage data is collected or transmitted
- **Your Control**: You can exclude repositories and delete your data anytime
- **Configurable Retention**: Set how long data is kept (default: 90 days)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.
