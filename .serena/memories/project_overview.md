# Project Overview

## Purpose
Real-time usage tracking statusline plugin for Claude Code 2.x that provides intelligent monitoring of:
- Context window usage (token tracking)
- Cost tracking (5-hour session window)
- Daily usage tracking (24-hour cycle aligned with weekly reset)
- Weekly usage tracking (calibrated to official Anthropic console)
- Session timer countdown
- Active Claude Code sessions
- Token burn rate

## Tech Stack
- **Language**: Bash shell scripting
- **Dependencies**:
  - `jq` - JSON processing (required)
  - `ccusage` (npm package v17.1.0) - Usage data extraction from Claude Code transcripts
  - Standard bash utilities (date, grep, etc.)
- **Platform**: macOS (primary), Linux, WSL (not native Windows)
- **Integration**: Claude Code statusLine configuration

## Architecture Pattern
**Shim Architecture** - Two-layer design for stable interface:
```
Claude Code → ~/.claude/statusline.sh (2-line shim)
                     ↓
              ~/Projects/cc-statusline/src/statusline.sh (implementation)
```

This allows flexible reorganization of implementation while maintaining a stable interface for Claude Code.

## Key Features
1. **Multi-layer progress visualization** - Auto-scaled bars with configurable thresholds (30%/50%/100%)
2. **Dual tracking schemes** - ISO week (`ccusage`) or official reset schedule (`ccusage_r`)
3. **Daily projection** - End-of-day cost projection using 5-hour window data
4. **Conditional rendering** - Only computes enabled sections for performance
5. **Caching system** - Daily and weekly cost caching to reduce ccusage calls
6. **Configurable colors** - Per-layer color customization via JSON config
7. **Privacy-first** - User config gitignored, no sensitive data in repo
