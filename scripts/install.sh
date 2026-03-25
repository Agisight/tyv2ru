#!/bin/bash
set -e

# ── Установка тувинско-русского переводчика ──
# Запускать один раз на сервере

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

echo "══════════════════════════════════════════"
echo "  Установка тувинско-русского переводчика"
echo "══════════════════════════════════════════"
echo ""

# ── 1. Системные зависимости ──
echo "[1/6] Системные зависимости..."
apt-get update -qq
apt-get install -y -qq cmake build-essential git python3-venv python3-pip > /dev/null

# ── 2. Python venv ──
echo "[2/6] Python окружение..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt

# ── 3. Собрать llama.cpp ──
echo "[3/6] Сборка llama.cpp..."
if [ ! -f "llama-server" ]; then
    if [ ! -d "llama.cpp" ]; then
        git clone --depth 1 https://github.com/ggml-org/llama.cpp
    fi
    cd llama.cpp
    cmake -B build -DGGML_CUDA=OFF -DCMAKE_BUILD_TYPE=Release
    cmake --build build --config Release -j$(nproc)
    cp build/bin/llama-server ../
    cd ..
    echo "  llama-server собран"
else
    echo "  llama-server уже есть"
fi

# ── 4. Скачать модель ──
echo "[4/6] Скачивание модели..."
mkdir -p models

# Читаем repo из конфига
HF_REPO=$(python3 -c "import yaml; c=yaml.safe_load(open('config/settings.yaml')); print(c['model']['hf_repo'])")
HF_FILE=$(python3 -c "import yaml; c=yaml.safe_load(open('config/settings.yaml')); print(c['model']['hf_file'])")

if [ ! -f "models/$HF_FILE" ]; then
    echo "  Скачивание $HF_REPO/$HF_FILE ..."
    huggingface-cli download "$HF_REPO" "$HF_FILE" --local-dir models/
else
    echo "  Модель уже скачана: models/$HF_FILE"
fi

# ── 5. Подготовить датасет для RAG ──
echo "[5/6] Подготовка RAG-датасета..."
mkdir -p data
if [ ! -f "data/tyv_rus_pairs.json" ]; then
    "$SCRIPT_DIR/prepare_dataset.sh"
else
    echo "  Датасет уже готов: data/tyv_rus_pairs.json"
fi

# ── 6. Готово ──
echo ""
echo "[6/6] Установка завершена!"
echo ""
echo "Запуск:  ./scripts/start.sh"
echo "Стоп:    ./scripts/stop.sh"
echo "Статус:  curl http://localhost:8077/health"
echo ""
