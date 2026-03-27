#!/bin/bash
# Quick test - run: bash scripts/test-quick.sh
echo "=== Health ==="
curl -s http://localhost:8077/health | python3 -m json.tool 2>/dev/null

echo ""
echo "=== Translate: tyv->ru ==="
curl -s http://localhost:8077/translate \
  -H "Content-Type: application/json" \
  -d '{"text":"Экии!","direction":"tyv2ru"}' | python3 -m json.tool 2>/dev/null

echo ""
echo "=== Translate: ru->tyv ==="
curl -s http://localhost:8077/translate \
  -H "Content-Type: application/json" \
  -d '{"text":"Привет!","direction":"ru2tyv"}' | python3 -m json.tool 2>/dev/null

echo ""
echo "=== Services ==="
systemctl is-active tyv2ru-llama tyv2ru-api
