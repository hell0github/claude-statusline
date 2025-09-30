# Claude Statusline

A custom statusline for [Claude Code 2.x](https://claude.com/claude-code) that provides real-time usage tracking with an intelligent multi-layer progress visualization, helping you stay aware of context windows, costs, and session limits.

## Features

- **Accurate context window tracking** - Counts reserved context space for Claude Sonnet 4.5
- **Cost usage tracking** - Re-calibrated to official '/usage' tracker, inspired by [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor), based on real Sonnet 4.5 API pricing
- **Multi-layer progression system** - Emphasizes first 50% (green, Sonnet 4.5 is token-effective), 100% usage in different layer (orange), overuse warning (red)
- **Weekly usage tracking** - Calibrated to official /usage data
- **Linear cost prediction** - Projects usage to end of 5-hour session
- **5-hour session reset/left time tracking** - Displays countdown until session limit resets
- **Active Claude Code sessions tracking** - Monitors concurrent sessions across projects
- **Lightweight bash implementation** - Runs entirely in shell, no heavy dependencies
- **Fully customizable** - Config file with feature toggles for enabling/disabling components
- **Privacy-first design** - Personal config excluded from version control
- **Tested on Max20 plan and macOS** - Compatible with Linux and WSL

## Platform Support

- **macOS** - ✅ Fully tested and supported
- **Linux** - ✅ Supported (requires bash, jq, npm)
- **Windows** - ⚠️ WSL or Git Bash only (not native CMD/PowerShell)

## Example Output

```
.claude | 45k/168k [████████░░] | $32/$140 [█████░░░░░] 23% | weekly 18% | 3h 42m | ×2
```

![Statusline Screenshot](./screenshots/statusline.png)
*Screenshot showing the multi-layer color system in action*

## Installation

### Quick Install (Recommended)

One command to install everything:

```bash
curl -sSL https://raw.githubusercontent.com/hell0github/claude-statusline/main/install.sh | bash
```

The installer will:
- ✅ Check dependencies (jq, ccusage)
- ✅ Copy files to ~/.claude/
- ✅ Prompt for your plan (pro/max5x/max20x)
- ✅ Ask permission before modifying settings.json
- ✅ Create backup of existing settings
- ✅ Guide you through setup

### Manual Installation

**Prerequisites:** [Claude Code](https://claude.com/claude-code), `jq` (`brew install jq`), `ccusage` (`npm install -g ccusage`)

```bash
# Clone and install
git clone https://github.com/hell0github/claude-statusline.git
cd claude-statusline
./install.sh

# OR copy manually:
cp statusline.sh ~/.claude/
cp statusline-config.example.json ~/.claude/statusline-config.json
chmod +x ~/.claude/statusline.sh

# Edit config (set your plan)
nano ~/.claude/statusline-config.json

# Add to ~/.claude/settings.json:
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}

# Restart Claude Code
```

## Configuration

Edit `~/.claude/statusline-config.json` to customize your statusline:

- **`user.plan`** - Set to `"pro"`, `"max5x"`, or `"max20x"` (your subscription tier)
- **`limits.*`** - Adjust weekly/context/cost limits if needed
  - Note: `pro` and `max5x` weekly limits are estimated - only `max20x` (850) has been verified
- **`display.*`** - Change bar length, performance tuning
- **`colors.*`** - Customize ANSI color codes for each element
- **`multi_layer.*`** - Adjust layer thresholds (50%, 100%, 105%) and multipliers (2x, 2x, 20x)

See `statusline-config.example.json` for all available options with detailed comments.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Statusline doesn't appear | `chmod +x ~/.claude/statusline.sh` and restart Claude Code |
| "jq: command not found" | `brew install jq` (macOS) or `sudo apt-get install jq` (Linux) |
| "Window tracking unavailable" | `npm install -g ccusage` |
| Wrong usage data | Update `user.plan` in config, verify with `ccusage blocks --active` |
| Colors not working | Check terminal 256-color support |

## File Structure

```
claude-statusline/
├── README.md                        # Documentation
├── LICENSE                          # MIT License
├── .gitignore                       # Excludes personal config
├── install.sh                       # Automated installer
├── statusline.sh                    # Main statusline script
├── statusline-config.example.json   # Template configuration
└── statusline-config.json           # Your personal config (not tracked)
```

## License

MIT License - See [LICENSE](LICENSE) file for details.

Free to use, modify, and distribute. No warranty provided.

## Acknowledgments

- Plugin for [Claude Code](https://claude.com/claude-code)
- Uses [ccusage](https://www.npmjs.com/package/ccusage) for usage tracking
- Inspired by [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)
- Thanks to the community for better usage awareness in AI-assisted coding

---

**Note:** This is an unofficial third-party tool and is not affiliated with or endorsed by Anthropic.
