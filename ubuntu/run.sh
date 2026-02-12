#!/bin/bash
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate
echo "Installing dependencies..."
pip install -r requirements.txt

echo "Starting GridClicker (Ubuntu)..."
# Note: On some systems, pynput requires access to /dev/input devices.
# If it fails, try running with sudo, though PyQt usually prefers non-root.
# A common fix for X11 is ensuring you are in the 'input' group.
python3 -u main.py
