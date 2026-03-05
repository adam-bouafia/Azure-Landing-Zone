#!/bin/bash
# ============================================================================
# Bicep Validation Script
# ============================================================================
#
# WHAT THIS DOES:
#   Validates all Bicep files in the infra/ directory by:
#   1. Linting — checks for style issues, best practices, unused params
#   2. Building — compiles Bicep to ARM JSON to catch syntax/type errors
#
#   If any file fails, the script exits with error code 1.
#   This is used in the CI pipeline to catch issues before deployment.
#
# WHY TWO STEPS:
#   Lint catches code quality issues (like missing @description decorators).
#   Build catches actual compilation errors (wrong types, missing params).
#   A file can pass lint but fail build (e.g., referencing a nonexistent module).
#
# USAGE:
#   chmod +x scripts/bash/validate-bicep.sh
#   ./scripts/bash/validate-bicep.sh
#
# ============================================================================

set -euo pipefail

# Colors for output readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

echo -e "${YELLOW}=== Bicep Linting ===${NC}"
echo ""

# Find all .bicep files (modules and main files)
while IFS= read -r file; do
    echo -n "  Linting: $file ... "
    if az bicep lint --file "$file" 2>&1 | grep -q "Error"; then
        echo -e "${RED}FAILED${NC}"
        az bicep lint --file "$file"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}OK${NC}"
    fi
done < <(find infra/ -name "*.bicep" -type f)

echo ""
echo -e "${YELLOW}=== Bicep Build (compile to ARM) ===${NC}"
echo ""

# Build only top-level files (not modules — they're compiled as part of main)
# Modules reference other modules via relative paths, so building a module
# in isolation would fail if it imports other modules.
while IFS= read -r file; do
    echo -n "  Building: $file ... "
    if az bicep build --file "$file" --stdout > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        az bicep build --file "$file" 2>&1
        ERRORS=$((ERRORS + 1))
    fi
done < <(find infra/ -name "*.bicep" -not -path "*/modules/*" -type f)

echo ""
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}=== VALIDATION FAILED: $ERRORS error(s) found ===${NC}"
    exit 1
else
    echo -e "${GREEN}=== All validations passed ===${NC}"
    exit 0
fi
