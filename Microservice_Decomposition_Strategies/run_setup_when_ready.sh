#!/bin/bash
# Helper script to run setup.sh when it's available

if [ ! -f setup.sh ] || [ ! -s setup.sh ]; then
    echo "❌ setup.sh is empty or doesn't exist"
    exit 1
fi

if [ ! -x setup.sh ]; then
    chmod +x setup.sh
fi

echo "Running setup.sh..."
bash setup.sh
