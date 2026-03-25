#!/bin/bash
set -e

# ── Запуск переводчика (llama.cpp + FastAPI) ──

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

source venv/bin/activate 2>/dev/null || true

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
    echo "Модель не найдена: $MODEL"
    echo "Запустите: ./scripts/install.sh"
    exit 1
fi

# ── Остановить предыдущие процессы ──
"$SCRIPT_DIR/stop.sh" 2>/dev/null || true

echo "══════════════════════════════════════════"
echo "  Тувинско-русский переводчик"
echo "══════════════════════════════════════════"
echo ""
echo "  Модель:  $MODEL"
echo "  Потоки:  $THREADS"
echo "  Порт:    $PORT"
echo "  RAG:     $(python3 -c "import yaml; print(yaml.safe_load(open('config/settings.yaml'))['rag']['enabled'])")"
echo ""

# ── 1. Запуск llama.cpp (фон) ──
echo "Запуск llama.cpp на порту $LLAMA_PORT..."
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
echo "  PID: $(cat .llama.pid)"

# Ждём готовности
echo -n "  Ожидание..."
for i in $(seq 1 30); do
    if curl -s "http://127.0.0.1:$LLAMA_PORT/health" > /dev/null 2>&1; then
        echo " готов!"
        break
    fi
    sleep 1
    echo -n "."
done

# ── 2. Запуск FastAPI (фон) ──
echo "Запуск API-сервера на порту $PORT..."
python3 -m uvicorn server:app \
    --host "$HOST" \
    --port "$PORT" \
    --log-level warning \
    > logs/server.log 2>&1 &

echo $! > .server.pid
echo "  PID: $(cat .server.pid)"

sleep 2

echo ""
echo "Готово!"
echo "  API:     http://$HOST:$PORT/translate"
echo "  Чат:     http://$HOST:$LLAMA_PORT"
echo "  Здоровье: http://$HOST:$PORT/health"
echo ""
echo "  Логи: tail -f logs/llama.log logs/server.log"
echo "  Стоп: ./scripts/stop.sh"
