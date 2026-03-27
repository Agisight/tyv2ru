#!/bin/bash
# Fix: remove repeat_penalty, lower max_tokens
# Run: bash scripts/fix-generation.sh

set -e

INSTALL_PATH="/opt/translator/tyv2ru"

cat > /etc/systemd/system/tyv2ru-llama.service << EOF
[Unit]
Description=Tyv2Ru llama.cpp
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_PATH
ExecStart=$INSTALL_PATH/llama-server \
    -m $INSTALL_PATH/models/gemma-3-1b-it.Q4_K_M.gguf \
    --host 127.0.0.1 \
    --port 8078 \
    --threads 4 \
    --ctx-size 2048 \
    --n-predict 32 \
    --temp 0.0 \
    --top-k 1
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=tyv2ru-llama

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart tyv2ru-llama
sleep 5
systemctl restart tyv2ru-api

echo "Fixed. Testing..."
sleep 2
curl -s http://localhost:8077/health | python3 -m json.tool 2>/dev/null
echo ""
bash scripts/test-quick.sh 2>/dev/null || true
