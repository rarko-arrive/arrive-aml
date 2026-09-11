#!/bin/bash
# Happy Path Test for arrive-aml + azureml-skills on rarko2
# Run this after cloning arrive-aml on a fresh Azure ML VM

set -e  # Exit on error

echo "=========================================="
echo "🧪 Testing arrive-aml + azureml-skills"
echo "=========================================="
echo

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test 1: Verify we're in arrive-aml
echo -e "${BLUE}Test 1: Verify arrive-aml repository${NC}"
if [ ! -f "scripts/setup-vm.sh" ]; then
    echo -e "${RED}❌ Not in arrive-aml directory${NC}"
    exit 1
fi
echo -e "${GREEN}✅ In arrive-aml repository${NC}"
echo

# Test 2: Check SSH to GitHub
echo -e "${BLUE}Test 2: GitHub SSH connection${NC}"
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo -e "${GREEN}✅ GitHub SSH working${NC}"
else
    echo -e "${YELLOW}⚠️  GitHub SSH not working${NC}"
    echo "Run: ssh -T git@github.com"
    echo "Expected: 'Hi rarko-arrive! You've successfully authenticated'"
    exit 1
fi
echo

# Test 3: Check if mirror directory exists
echo -e "${BLUE}Test 3: Mirror directory setup${NC}"
if [ -d "/mnt/mirror" ]; then
    echo -e "${GREEN}✅ /mnt/mirror exists${NC}"
else
    echo -e "${YELLOW}⚠️  /mnt/mirror doesn't exist, creating...${NC}"
    sudo mkdir -p /mnt/mirror
    sudo chown $USER:$USER /mnt/mirror
    echo -e "${GREEN}✅ Created /mnt/mirror${NC}"
fi
echo

# Test 4: Check if repo is in canonical location
echo -e "${BLUE}Test 4: Repository location${NC}"
CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" == *"/cloudfiles/rarko/main/arrive-aml"* ]]; then
    echo -e "${GREEN}✅ Repository in canonical location${NC}"
else
    echo -e "${YELLOW}⚠️  Repository not in canonical location${NC}"
    echo "Current: $CURRENT_DIR"
    echo "Expected: ~/cloudfiles/rarko/main/arrive-aml"
    echo
    echo "To move:"
    echo "  mkdir -p ~/cloudfiles/rarko/main"
    echo "  mv $CURRENT_DIR ~/cloudfiles/rarko/main/"
fi
echo

# Test 5: Test git performance
echo -e "${BLUE}Test 5: Git performance (should be fast)${NC}"
START=$(date +%s.%N)
git status > /dev/null 2>&1
END=$(date +%s.%N)
DURATION=$(echo "$END - $START" | bc)
echo "Git status took: ${DURATION}s"
if (( $(echo "$DURATION < 10" | bc -l) )); then
    echo -e "${GREEN}✅ Git performance acceptable (<10s)${NC}"
else
    echo -e "${YELLOW}⚠️  Git slow (>10s), worktree will help${NC}"
fi
echo

# Test 6: Check Claude CLI
echo -e "${BLUE}Test 6: Claude CLI installation${NC}"
if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>&1 || echo "unknown")
    echo -e "${GREEN}✅ Claude CLI installed: $CLAUDE_VERSION${NC}"
else
    echo -e "${YELLOW}⚠️  Claude CLI not found${NC}"
    echo "Install with: curl -fsSL https://claude.ai/install.sh | sh"
fi
echo

# Test 7: Check if azureml-skills is installable
echo -e "${BLUE}Test 7: azureml-skills repository accessibility${NC}"
if git ls-remote git@github.com:rarko-arrive/azureml-skills.git HEAD &> /dev/null; then
    echo -e "${GREEN}✅ azureml-skills repository accessible${NC}"
else
    echo -e "${RED}❌ Cannot access azureml-skills repository${NC}"
    echo "Check: git ls-remote git@github.com:rarko-arrive/azureml-skills.git HEAD"
    exit 1
fi
echo

# Test 8: Check documentation files
echo -e "${BLUE}Test 8: Documentation files${NC}"
if [ -f "CLAUDE-SETUP.md" ]; then
    echo -e "${GREEN}✅ CLAUDE-SETUP.md exists${NC}"
else
    echo -e "${RED}❌ CLAUDE-SETUP.md not found${NC}"
    exit 1
fi

if [ -f "instruct.md" ]; then
    echo -e "${GREEN}✅ instruct.md exists${NC}"
else
    echo -e "${RED}❌ instruct.md not found${NC}"
    exit 1
fi
echo

# Test 9: Setup mirror worktree
echo -e "${BLUE}Test 9: Setting up mirror worktree${NC}"
if [ -d "/mnt/mirror/arrive-aml" ]; then
    echo -e "${YELLOW}⚠️  Mirror already exists, skipping${NC}"
else
    echo "Running: bash scripts/lib/setup-mirror-worktree.sh arrive-aml"
    if bash scripts/lib/setup-mirror-worktree.sh arrive-aml; then
        echo -e "${GREEN}✅ Mirror worktree created${NC}"
    else
        echo -e "${RED}❌ Failed to create mirror worktree${NC}"
        exit 1
    fi
fi
echo

# Test 10: Verify mirror performance
echo -e "${BLUE}Test 10: Mirror git performance${NC}"
if [ -d "/mnt/mirror/arrive-aml" ]; then
    cd /mnt/mirror/arrive-aml
    START=$(date +%s.%N)
    git status > /dev/null 2>&1
    END=$(date +%s.%N)
    DURATION=$(echo "$END - $START" | bc)
    echo "Mirror git status took: ${DURATION}s"
    if (( $(echo "$DURATION < 1" | bc -l) )); then
        echo -e "${GREEN}✅ Mirror is FAST! (<1s)${NC}"
    else
        echo -e "${YELLOW}⚠️  Mirror slower than expected${NC}"
    fi
    cd - > /dev/null
else
    echo -e "${YELLOW}⚠️  Mirror not created, skipping${NC}"
fi
echo

# Summary
echo "=========================================="
echo -e "${GREEN}🎉 Happy Path Test Complete!${NC}"
echo "=========================================="
echo
echo "Next steps:"
echo "1. Read CLAUDE-SETUP.md for Claude Code installation"
echo "2. Install azureml-skills marketplace"
echo "3. Test /work-in-repo skill"
echo
echo "Quick commands:"
echo "  cat CLAUDE-SETUP.md          # Read setup guide"
echo "  cd /mnt/mirror/arrive-aml    # Work in fast mirror"
echo "  /work-in-repo                # Use the skill (in Claude Code)"
echo
