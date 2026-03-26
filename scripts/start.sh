#!/bin/bash
set -e

# ── Запуск переводчика (llama.cpp + FastAPI) ──

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

# ── Цвета ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Проверка: установлен ли переводчик? ──
if [ ! -f "llama-server" ] || [ ! -d "venv" ]; then
    echo -e "${YELLOW}Переводчик не установлен. Запускаю установку...${NC}"
    echo ""
    "$SCRIPT_DIR/install.sh"
    echo ""
fi

source venv/bin/activate 2>/dev/null || { echo -e "${RED}venv не найден. Запустите: ./scripts/install.sh${NC}"; exit 1; }

mkdir -p logs

# Читаем настройки из конфига
SETTINGS=$(python3 -c "
import yaml, os
with open('config/settings.yaml') as f:
    c = yaml.safe_load(f)
threads = os.cpu_count() if c['model']['threads'] == 'auto' else c['model']['threads']
print(f\"{c['model']['path']}|{threads}|{c['model']['ctx_size']}|{c['model']['max_tokens']}|{c['model']['temp']}|{c['model']['top_k']}|{c['model']['repeat_penalty']}|{c['server']['llama_port']}|{c['server']['host']}|{c['server']['port']}\")
")

IFS='|' read -r MODEL THREADS CTX MAX_TOK TEMP TOP_K REP_PEN LLAMA_PORT HOST PORT <<< "$SETTINGS"

# ── Проверка модели ──
if [ ! -f "$MODEL" ]; then
    echo -e "${RED}Модель не найдена: $MODEL${NC}"
    echo "Запустите: ./scripts/install.sh"
    exit 1
fi

# ── Остановить предыдущие процессы ──
"$SCRIPT_DIR/stop.sh" 2>/dev/null || true

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Тувинско-русский переводчик${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""
echo "  Модель:  $MODEL"
echo "  Потоки:  $THREADS"
echo "  Порт:    $PORT"
echo "  RAG:     $(python3 -c "import yaml; print(yaml.safe_load(open('config/settings.yaml'))['rag']['enabled'])")"
echo ""

# ── 1. Запуск llama.cpp (фон) ──
echo -n "  Запуск llama.cpp на порту $LLAMA_PORT..."
./llama-server \
    -m "$MODEL" \
    --host 127.0.0.1 \
    --port "$LLAMA_PORT" \
    --threads "$THREADS" \
    --ctx-size "$CTX" \
    --n-predict "$MAX_TOK" \
    --temp "$TEMP" \
    --top-k "$TOP_K" \
    --repeat-penalty "$REP_PEN" \
    > logs/llama.log 2>&1 &

echo $! > .llama.pid

# Ждём готовности
for i in $(seq 1 60); do
    if curl -s "http://127.0.0.1:$LLAMA_PORT/health" > /dev/null 2>&1; then
        echo -e " ${GREEN}готов!${NC} (PID $(cat .llama.pid))"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e " ${RED}таймаут!${NC}"
        echo "  Проверьте: tail -f logs/llama.log"
        exit 1
    fi
    echo -n "."
    sleep 1
done

# ── 2. Запуск FastAPI (фон) ──
echo -n "  Запуск API-сервера на порту $PORT..."
python3 -m uvicorn server:app \
    --host "$HOST" \
    --port "$PORT" \
    --log-level warning \
    > logs/server.log 2>&1 &

echo $! > .server.pid

# Ждём готовности FastAPI
for i in $(seq 1 15); do
    if curl -s "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; then
        echo -e " ${GREEN}готов!${NC} (PID $(cat .server.pid))"
        break
    fi
    if [ $i -eq 15 ]; then
        echo -e " ${YELLOW}запущен, но health не отвечает${NC}"
    fi
    sleep 1
done

echo ""
echo -e "${GREEN}  Готово!${NC}"
echo ""
echo "  Веб-чат:     http://localhost:$PORT"
echo "  API:         http://localhost:$PORT/translate"
echo "  Здоровье:    http://localhost:$PORT/health"
echo ""
echo "  Логи:  tail -f logs/llama.log logs/server.log"
echo "  Стоп:  ./scripts/stop.sh"
echo ""
