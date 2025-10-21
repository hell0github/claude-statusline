#!/bin/bash

# Claude Statusline - Installation Script (v2.1)
# https://github.com/hell0github/claude-statusline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PLAN=""
INSTALL_PATH=""
AUTO_UPDATE_SETTINGS="ask"  # ask, yes, no
NON_INTERACTIVE=false
SKIP_DEPS_CHECK=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --plan)
            PLAN="$2"
            shift 2
            ;;
        --install-path)
            INSTALL_PATH="$2"
            shift 2
            ;;
        --auto-update-settings)
            AUTO_UPDATE_SETTINGS="yes"
            shift
            ;;
        --no-update-settings)
            AUTO_UPDATE_SETTINGS="no"
            shift
            ;;
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --skip-deps-check)
            SKIP_DEPS_CHECK=true
            shift
            ;;
        --help|-h)
            echo "Claude Statusline Installer v2.1"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --plan PLAN              Set plan: pro, max5x, or max20x (default: max20x)"
            echo "  --install-path PATH      Installation directory (default: ~/Projects/cc-statusline)"
            echo "  --auto-update-settings   Automatically update settings.json"
            echo "  --no-update-settings     Skip settings.json update"
            echo "  --non-interactive, -y    Run without prompts (uses defaults)"
            echo "  --skip-deps-check        Skip dependency checks"
            echo "  --help, -h               Show this help message"
            echo ""
            echo "Examples:"
            echo "  # Interactive install"
            echo "  ./install.sh"
            echo ""
            echo "  # Non-interactive with defaults"
            echo "  ./install.sh -y"
            echo ""
            echo "  # Non-interactive with specific plan"
            echo "  ./install.sh --plan max20x -y"
            echo ""
            echo "  # Piped install (curl)"
            echo "  curl -sSL URL | bash -s -- --plan max20x -y"
            exit 0
            ;;
        *)
            echo -e "${RED}✗ Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate plan if provided
if [ -n "$PLAN" ] && [[ ! "$PLAN" =~ ^(pro|max5x|max20x)$ ]]; then
    echo -e "${RED}✗ Invalid plan: $PLAN${NC}"
    echo "  Valid options: pro, max5x, max20x"
    exit 1
fi

# Detect if stdin is not a terminal (piped input)
if [ "$NON_INTERACTIVE" != true ] && [ ! -t 0 ]; then
    echo -e "${YELLOW}⚠ Warning: Detected non-interactive context (piped input)${NC}"
    echo "  Automatically enabling non-interactive mode"
    echo "  Use --help to see available options"
    echo ""
    NON_INTERACTIVE=true
fi

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Statusline Installer v2.1    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

if [ "$NON_INTERACTIVE" = true ]; then
    echo -e "${YELLOW}Running in non-interactive mode${NC}"
    echo ""
fi

# Check if Claude Code is installed
CLAUDE_DIR="$HOME/.claude"
if [ ! -d "$CLAUDE_DIR" ]; then
    echo -e "${RED}✗ Error: Claude Code directory not found at ~/.claude${NC}"
    echo -e "  Please install Claude Code first: https://claude.com/claude-code"
    exit 1
fi
echo -e "${GREEN}✓ Claude Code detected${NC}"

# Check dependencies
if [ "$SKIP_DEPS_CHECK" != true ]; then
    echo ""
    echo "Checking dependencies..."

    # Check jq
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠ jq not found (required for JSON processing)${NC}"
        echo -e "  Install with: ${BLUE}brew install jq${NC} (macOS)"
        if [ "$NON_INTERACTIVE" = true ]; then
            echo -e "${YELLOW}Non-interactive mode: continuing without jq (limited functionality)${NC}"
        else
            read -p "Continue anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}✓ jq found${NC}"
    fi

    # Check npm for ccusage
    if ! command -v npm &> /dev/null; then
        echo -e "${YELLOW}⚠ npm not found (needed for ccusage)${NC}"
        echo -e "  Install Node.js: https://nodejs.org/"
        if [ "$NON_INTERACTIVE" = true ]; then
            echo -e "${YELLOW}Non-interactive mode: continuing without npm (install ccusage manually later)${NC}"
        else
            read -p "Continue anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}✓ npm found${NC}"

        # Check/install ccusage
        CCUSAGE_VERSION="17.1.0"
        if ! npm list -g ccusage &> /dev/null; then
            echo -e "${YELLOW}⚠ ccusage not installed${NC}"
            if [ "$NON_INTERACTIVE" = true ]; then
                echo -e "${YELLOW}Non-interactive mode: skipping ccusage install (install manually: npm install -g ccusage@${CCUSAGE_VERSION})${NC}"
            else
                read -p "Install ccusage@${CCUSAGE_VERSION} now? (y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    npm install -g "ccusage@${CCUSAGE_VERSION}"
                    echo -e "${GREEN}✓ ccusage@${CCUSAGE_VERSION} installed${NC}"
                fi
            fi
        else
            echo -e "${GREEN}✓ ccusage found${NC}"
        fi
    fi
fi

# Determine installation directory
echo ""
echo -e "${BLUE}Installation Location${NC}"

# Detect if we're running from a repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/src/statusline.sh" ] && [ -f "$SCRIPT_DIR/config/config.example.json" ]; then
    # Running from repo
    echo "Running from repository at: ${BLUE}$SCRIPT_DIR${NC}"

    if [ -n "$INSTALL_PATH" ]; then
        # Command-line path provided
        INSTALL_DIR="$INSTALL_PATH"
        echo -e "${GREEN}✓ Using specified path: $INSTALL_DIR${NC}"
    elif [ "$NON_INTERACTIVE" = true ]; then
        # Non-interactive: use repo location by default
        INSTALL_DIR="$SCRIPT_DIR"
        echo -e "${GREEN}✓ Using repository as installation directory (non-interactive default)${NC}"
    else
        # Interactive: offer choice
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
    fi
else
    # Curl install - need to git clone
    echo "Installing via curl/download method..."

    if [ -n "$INSTALL_PATH" ]; then
        INSTALL_DIR="$INSTALL_PATH"
    elif [ "$NON_INTERACTIVE" = true ]; then
        INSTALL_DIR="$HOME/Projects/cc-statusline"
        echo -e "${GREEN}✓ Using default path: $INSTALL_DIR${NC}"
    else
        read -p "Enter installation path [$HOME/Projects/cc-statusline]: " custom_path
        INSTALL_DIR="${custom_path:-$HOME/Projects/cc-statusline}"
    fi

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

    MIGRATE_CONFIG=true
    if [ "$NON_INTERACTIVE" = true ]; then
        echo -e "${GREEN}Non-interactive mode: automatically migrating settings${NC}"
    else
        read -p "Migrate settings to new location? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            MIGRATE_CONFIG=false
        fi
    fi

    if [ "$MIGRATE_CONFIG" = true ]; then
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

    # Only prompt if plan not already set via CLI or config
    if [ -z "$PLAN" ]; then
        if [ -z "$CURRENT_PLAN" ] || [ "$OLD_INSTALL" = false ]; then
            if [ "$NON_INTERACTIVE" = true ]; then
                # Non-interactive: default to max20x
                PLAN="max20x"
                echo ""
                echo -e "${GREEN}Non-interactive mode: defaulting to $PLAN plan${NC}"
            else
                # Interactive: prompt for selection
                echo ""
                echo "Configure your Claude plan:"
                echo "  1) pro"
                echo "  2) max5x"
                echo "  3) max20x"
                read -p "Select your plan (1-3) [3]: " -n 1 -r plan_choice
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
                    *)
                        PLAN="max20x"
                        ;;
                esac
            fi
        else
            PLAN="$CURRENT_PLAN"
        fi
    fi

    # Update config with selected plan
    if [ -n "$PLAN" ]; then
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

        # Determine if we should update settings
        UPDATE_SETTINGS=false
        if [ "$AUTO_UPDATE_SETTINGS" = "yes" ]; then
            UPDATE_SETTINGS=true
            echo -e "${GREEN}Auto-update enabled: updating settings.json${NC}"
        elif [ "$AUTO_UPDATE_SETTINGS" = "no" ]; then
            UPDATE_SETTINGS=false
            echo -e "${YELLOW}Skipping settings.json update (--no-update-settings)${NC}"
            echo "  Manual step required: Add statusline to settings.json"
        elif [ "$NON_INTERACTIVE" = true ]; then
            # In non-interactive mode, default to updating
            UPDATE_SETTINGS=true
            echo -e "${GREEN}Non-interactive mode: updating settings.json${NC}"
        else
            read -p "Update settings.json automatically? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                UPDATE_SETTINGS=true
            fi
        fi

        if [ "$UPDATE_SETTINGS" = true ]; then
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
