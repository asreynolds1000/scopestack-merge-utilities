#!/bin/bash
# Install git pre-commit hook for sensitive data checking

HOOK_PATH=".git/hooks/pre-commit"

cat > "$HOOK_PATH" << 'EOF'
#!/bin/bash
# Pre-commit hook to check for sensitive data

echo "Checking for sensitive data..."
python3 scripts/check-sensitive-data.py --staged-only

if [ $? -ne 0 ]; then
    echo ""
    echo "Commit aborted. Please fix the issues above."
    exit 1
fi
EOF

chmod +x "$HOOK_PATH"
echo "Pre-commit hook installed successfully."
