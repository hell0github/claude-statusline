#!/bin/bash

# Claude Statusline - Safe Installation Script
# https://github.com/hell0github/claude-statusline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Statusline Installer         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if Claude Code is installed
CLAUDE_DIR="$HOME/.claude"
if [ ! -d "$CLAUDE_DIR" ]; then
    echo -e "${RED}✗ Error: Claude Code directory not found at ~/.claude${NC}"
    echo -e "  Please install Claude Code first: https://claude.com/claude-code"
    exit 1
fi
echo -e "${GREEN}✓ Claude Code detected${NC}"

# Check dependencies
echo ""
echo "Checking dependencies..."

# Check jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠ jq not found (required for JSON processing)${NC}"
    echo -e "  Install with: ${BLUE}brew install jq${NC} (macOS) or ${BLUE}sudo apt-get install jq${NC} (Linux)"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✓ jq found${NC}"
fi

# Check npm for ccusage
if ! command -v npm &> /dev/null; then
    echo -e "${YELLOW}⚠ npm not found (needed for ccusage)${NC}"
    echo -e "  Install Node.js: https://nodejs.org/"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✓ npm found${NC}"

    # Check/install ccusage
    CCUSAGE_VERSION="17.1.0"
    if ! npm list -g ccusage &> /dev/null; then
        echo -e "${YELLOW}⚠ ccusage not installed${NC}"
        read -p "Install ccusage@${CCUSAGE_VERSION} now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            npm install -g "ccusage@${CCUSAGE_VERSION}"
            echo -e "${GREEN}✓ ccusage@${CCUSAGE_VERSION} installed${NC}"
        fi
    else
        echo -e "${GREEN}✓ ccusage found${NC}"
    fi
fi

# Download/copy files
echo ""
echo "Installing statusline files..."

# Determine script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're in the repo or need to download
if [ -f "$SCRIPT_DIR/statusline.sh" ] && [ -f "$SCRIPT_DIR/statusline-config.example.json" ]; then
    # Running from cloned repo
    echo -e "${GREEN}✓ Running from repository${NC}"
    cp "$SCRIPT_DIR/statusline.sh" "$CLAUDE_DIR/"
    cp "$SCRIPT_DIR/statusline-config.example.json" "$CLAUDE_DIR/statusline-config.json"
else
    # Download from GitHub
    echo "Downloading files from GitHub..."
    REPO_URL="https://raw.githubusercontent.com/hell0github/claude-statusline/main"
    curl -sSL "$REPO_URL/statusline.sh" -o "$CLAUDE_DIR/statusline.sh"
    curl -sSL "$REPO_URL/statusline-config.example.json" -o "$CLAUDE_DIR/statusline-config.json"
fi

# Make executable
chmod +x "$CLAUDE_DIR/statusline.sh"
echo -e "${GREEN}✓ Files copied to ~/.claude/${NC}"

# Prompt for plan selection
echo ""
echo "Configure your Claude plan:"
echo "  1) pro"
echo "  2) max5x"
echo "  3) max20x"
read -p "Select your plan (1-3): " -n 1 -r plan_choice
echo

case $plan_choice in
    1)
        PLAN="pro"
        echo -e "${YELLOW}Note: pro weekly limit (300) is estimated, not verified${NC}"
        ;;
    2)
        PLAN="max5x"
        echo -e "${YELLOW}Note: max5x weekly limit (500) is estimated, not verified${NC}"
        ;;
    3) PLAN="max20x" ;;
    *)
        echo -e "${YELLOW}Invalid choice, defaulting to max5x${NC}"
        echo -e "${YELLOW}Note: max5x weekly limit (500) is estimated, not verified${NC}"
        PLAN="max5x"
        ;;
esac

# Update config with selected plan
if command -v jq &> /dev/null; then
    jq --arg plan "$PLAN" '.user.plan = $plan' "$CLAUDE_DIR/statusline-config.json" > "$CLAUDE_DIR/statusline-config.json.tmp"
    mv "$CLAUDE_DIR/statusline-config.json.tmp" "$CLAUDE_DIR/statusline-config.json"
    echo -e "${GREEN}✓ Config set to $PLAN plan${NC}"
else
    echo -e "${YELLOW}⚠ jq not available, please manually set plan in config${NC}"
fi

# Update settings.json (with safety)
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
echo ""
echo -e "${BLUE}Settings.json Update${NC}"
echo "The statusline needs to be enabled in your Claude Code settings."
echo ""

if [ -f "$SETTINGS_FILE" ]; then
    echo "Current settings.json exists."
    echo -e "${YELLOW}⚠ This will modify your existing settings${NC}"
else
    echo "No settings.json found, will create new one."
fi

echo ""
read -p "Update settings.json automatically? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Create backup
    if [ -f "$SETTINGS_FILE" ]; then
        BACKUP_FILE="$SETTINGS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SETTINGS_FILE" "$BACKUP_FILE"
        echo -e "${GREEN}✓ Backup created: $BACKUP_FILE${NC}"
    fi

    # Update settings
    if command -v jq &> /dev/null; then
        if [ -f "$SETTINGS_FILE" ]; then
            # Merge with existing settings
            jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}' \
                "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && \
                mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            echo -e "${GREEN}✓ settings.json updated (existing settings preserved)${NC}"
        else
            # Create new settings file
            cat > "$SETTINGS_FILE" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
EOF
            echo -e "${GREEN}✓ settings.json created${NC}"
        fi
    else
        echo -e "${RED}✗ jq not available, cannot safely update settings.json${NC}"
        echo -e "  Please add manually (see below)"
    fi
else
    echo -e "${YELLOW}⚠ Skipped automatic update${NC}"
fi

# Show manual instructions if needed
if [[ ! $REPLY =~ ^[Yy]$ ]] || ! command -v jq &> /dev/null; then
    echo ""
    echo -e "${BLUE}Manual Setup:${NC}"
    echo "Add this to ~/.claude/settings.json:"
    echo ""
    echo '{'
    echo '  "statusLine": {'
    echo '    "type": "command",'
    echo '    "command": "~/.claude/statusline.sh"'
    echo '  }'
    echo '}'
    echo ""
fi

# Final instructions
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation Complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Review config: ~/.claude/statusline-config.json"
echo "  2. Restart Claude Code"
echo "  3. Enjoy your new statusline!"
echo ""
echo "Troubleshooting:"
echo "  - If statusline doesn't appear, restart Claude Code"
echo "  - Verify permissions: chmod +x ~/.claude/statusline.sh"
echo "  - Check settings: cat ~/.claude/settings.json"
echo ""
echo -e "${BLUE}Repository: https://github.com/hell0github/claude-statusline${NC}"
echo ""
