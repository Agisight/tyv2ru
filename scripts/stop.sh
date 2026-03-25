#!/bin/bash

# ── Остановка переводчика ──

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

stopped=0

if [ -f .llama.pid ]; then
    PID=$(cat .llama.pid)
    if kill "$PID" 2>/dev/null; then
        echo "llama.cpp остановлен (PID $PID)"
        stopped=1
    fi
    rm -f .llama.pid
fi

if [ -f .server.pid ]; then
    PID=$(cat .server.pid)
    if kill "$PID" 2>/dev/null; then
        echo "API-сервер остановлен (PID $PID)"
        stopped=1
    fi
    rm -f .server.pid
fi

if [ $stopped -eq 0 ]; then
    echo "Ничего не запущено"
fi
