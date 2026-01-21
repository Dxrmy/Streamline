#!/bin/bash

echo "Installing AI Lesson Planner..."

# 1. System Dependencies
sudo apt-get update
sudo apt-get install -y python3-venv python3-pip libxml2-dev libxslt-dev

# 2. Virtual Env
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate

# 3. Python Deps
pip install -r requirements.txt
playwright install chromium

# 4. Service
echo "Setting up systemd service..."
sudo cp ai_lesson_planner.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ai_lesson_planner
sudo systemctl start ai_lesson_planner

echo "Installation Complete! Service is running."
