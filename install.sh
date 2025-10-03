#!/bin/bash

# Claude Statusline - Installation Script (v2.0)
# https://github.com/hell0github/claude-statusline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Statusline Installer v2.0    ║${NC}"
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

# Determine installation directory
echo ""
echo -e "${BLUE}Installation Location${NC}"

# Detect if we're running from a repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/src/statusline.sh" ] && [ -f "$SCRIPT_DIR/config/config.example.json" ]; then
    # Running from repo - offer to use repo location or custom
    echo "Running from repository at: ${BLUE}$SCRIPT_DIR${NC}"
    echo ""
    echo "Installation options:"
    echo "  1) Use repository location (recommended for development)"
    echo "  2) Install to custom location"
    read -p "Select option (1-2) [1]: " -n 1 -r install_choice
    echo

    if [ -z "$install_choice" ] || [ "$install_choice" = "1" ]; then
        INSTALL_DIR="$SCRIPT_DIR"
        echo -e "${GREEN}✓ Using repository as installation directory${NC}"
    else
        read -p "Enter installation path [$HOME/Projects/cc-statusline]: " custom_path
        INSTALL_DIR="${custom_path:-$HOME/Projects/cc-statusline}"
    fi
else
    # Curl install - need to git clone
    echo "Installing via curl method..."
    read -p "Enter installation path [$HOME/Projects/cc-statusline]: " custom_path
    INSTALL_DIR="${custom_path:-$HOME/Projects/cc-statusline}"

    # Clone repository if directory doesn't exist
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "Cloning repository to $INSTALL_DIR..."
        git clone https://github.com/hell0github/claude-statusline.git "$INSTALL_DIR"
        echo -e "${GREEN}✓ Repository cloned${NC}"
    else
        echo -e "${YELLOW}⚠ Directory exists, using existing files${NC}"
    fi

    SCRIPT_DIR="$INSTALL_DIR"
fi

# Expand tilde in path
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

# Create installation directory if needed
mkdir -p "$INSTALL_DIR"
echo -e "${GREEN}✓ Installation directory: $INSTALL_DIR${NC}"

# If not using repo location, copy files
if [ "$INSTALL_DIR" != "$SCRIPT_DIR" ]; then
    echo ""
    echo "Copying files to $INSTALL_DIR..."

    # Create structure
    mkdir -p "$INSTALL_DIR/src"
    mkdir -p "$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR/data"

    # Copy source files
    cp "$SCRIPT_DIR/src/statusline.sh" "$INSTALL_DIR/src/"
    cp "$SCRIPT_DIR/src/statusline-utils.sh" "$INSTALL_DIR/src/" 2>/dev/null || echo -e "${YELLOW}⚠ statusline-utils.sh not found (optional)${NC}"
    cp "$SCRIPT_DIR/config/config.example.json" "$INSTALL_DIR/config/"

    echo -e "${GREEN}✓ Files copied${NC}"
fi

# Create config if doesn't exist
CONFIG_FILE="$INSTALL_DIR/config/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    cp "$INSTALL_DIR/config/config.example.json" "$CONFIG_FILE"
    echo -e "${GREEN}✓ Created config.json${NC}"
else
    echo -e "${YELLOW}⚠ config.json exists, keeping existing configuration${NC}"
fi

# Create data directory
mkdir -p "$INSTALL_DIR/data"

# Create shim in ~/.claude/
SHIM_FILE="$CLAUDE_DIR/statusline.sh"

# Check for old installation
OLD_INSTALL=false
if [ -f "$SHIM_FILE" ]; then
    # Check if it's old style (full script) or new style (shim)
    if ! grep -q "exec.*src/statusline.sh" "$SHIM_FILE" 2>/dev/null; then
        OLD_INSTALL=true
        echo ""
        echo -e "${YELLOW}⚠ Old installation detected at ~/.claude/statusline.sh${NC}"
        echo "Creating backup and migrating to new architecture..."

        # Backup old installation
        BACKUP_FILE="$SHIM_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SHIM_FILE" "$BACKUP_FILE"
        echo -e "${GREEN}✓ Backup created: $BACKUP_FILE${NC}"
    fi
fi

# Create shim
echo ""
echo "Creating shim in ~/.claude/statusline.sh..."
cat > "$SHIM_FILE" << EOF
#!/bin/bash
exec "$INSTALL_DIR/src/statusline.sh" "\$@"
EOF
chmod +x "$SHIM_FILE"
echo -e "${GREEN}✓ Shim created${NC}"

# Migrate old config if exists
if [ "$OLD_INSTALL" = true ] && [ -f "$CLAUDE_DIR/statusline-config.json" ]; then
    echo ""
    echo -e "${YELLOW}Found old configuration at ~/.claude/statusline-config.json${NC}"
    read -p "Migrate settings to new location? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Merge settings (keep new format, update user preferences)
        if command -v jq &> /dev/null; then
            OLD_PLAN=$(jq -r '.user.plan // "max5x"' "$CLAUDE_DIR/statusline-config.json")
            jq --arg plan "$OLD_PLAN" '.user.plan = $plan' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
            mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            echo -e "${GREEN}✓ Settings migrated${NC}"
        fi

        # Backup old config
        mv "$CLAUDE_DIR/statusline-config.json" "$CLAUDE_DIR/statusline-config.json.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${GREEN}✓ Old config backed up${NC}"
    fi
fi

# Prompt for plan selection (if new installation or no plan set)
if command -v jq &> /dev/null; then
    CURRENT_PLAN=$(jq -r '.user.plan // ""' "$CONFIG_FILE")

    if [ -z "$CURRENT_PLAN" ] || [ "$OLD_INSTALL" = false ]; then
        echo ""
        echo "Configure your Claude plan:"
        echo "  1) pro"
        echo "  2) max5x"
        echo "  3) max20x"
        read -p "Select your plan (1-3) [2]: " -n 1 -r plan_choice
        echo

        case $plan_choice in
            1)
                PLAN="pro"
                echo -e "${YELLOW}Note: pro weekly limit (300) is estimated, not verified${NC}"
                ;;
            3) PLAN="max20x" ;;
            *)
                PLAN="max5x"
                echo -e "${YELLOW}Note: max5x weekly limit (500) is estimated, not verified${NC}"
                ;;
        esac

        # Update config with selected plan
        jq --arg plan "$PLAN" '.user.plan = $plan' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo -e "${GREEN}✓ Config set to $PLAN plan${NC}"
    fi
fi

# Update settings.json (with safety)
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
echo ""
echo -e "${BLUE}Settings.json Update${NC}"
echo "The statusline needs to be enabled in your Claude Code settings."
echo ""

if [ -f "$SETTINGS_FILE" ]; then
    # Check if already configured
    if grep -q "statusline.sh" "$SETTINGS_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ settings.json already configured${NC}"
    else
        echo "Current settings.json exists."
        echo -e "${YELLOW}⚠ This will modify your existing settings${NC}"
        echo ""
        read -p "Update settings.json automatically? (y/n): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Create backup
            BACKUP_FILE="$SETTINGS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$SETTINGS_FILE" "$BACKUP_FILE"
            echo -e "${GREEN}✓ Backup created: $BACKUP_FILE${NC}"

            # Update settings
            if command -v jq &> /dev/null; then
                jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}' \
                    "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && \
                    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
                echo -e "${GREEN}✓ settings.json updated${NC}"
            fi
        fi
    fi
else
    echo "No settings.json found, creating new one..."
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

# Final instructions
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation Complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Installation Summary:"
echo "  • Files: ${BLUE}$INSTALL_DIR${NC}"
echo "  • Config: ${BLUE}$CONFIG_FILE${NC}"
echo "  • Shim: ${BLUE}$SHIM_FILE${NC}"
echo ""
echo "Next steps:"
echo "  1. Review config: ${BLUE}$CONFIG_FILE${NC}"
echo "  2. Restart Claude Code"
echo "  3. Enjoy your new statusline!"
echo ""
echo "Configuration:"
echo "  • To customize: edit ${BLUE}$CONFIG_FILE${NC}"
echo "  • See all options: ${BLUE}$INSTALL_DIR/config/config.example.json${NC}"
echo ""
echo "Troubleshooting:"
echo "  - If statusline doesn't appear, restart Claude Code"
echo "  - Verify shim: cat ~/.claude/statusline.sh"
echo "  - Check settings: cat ~/.claude/settings.json"
echo "  - Test manually: echo '{}' | ~/.claude/statusline.sh"
echo ""
echo -e "${BLUE}Documentation: $INSTALL_DIR/README.md${NC}"
echo -e "${BLUE}Repository: https://github.com/hell0github/claude-statusline${NC}"
echo ""
