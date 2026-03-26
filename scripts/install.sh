#!/bin/bash
set -e

# ══════════════════════════════════════════════════════════════
#  Установка тувинско-русского переводчика — один скрипт
#
#  Использование:
#    git clone https://github.com/Agisight/tyv2ru.git
#    cd tyv2ru
#    ./scripts/install.sh          # обычный пользователь (запросит sudo)
#    sudo ./scripts/install.sh     # root
# ══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

# ── Цвета ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${CYAN}[$1/$TOTAL]${NC} $2"; }

TOTAL=6

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Тувинско-русский переводчик — установка${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# ── Определяем sudo ──
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        SUDO="sudo"
        echo -e "\n  Запущено не под root — буду использовать sudo"
    else
        fail "Запустите под root или установите sudo"
    fi
fi

# ── Делаем все скрипты исполняемыми ──
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

# ── 1. Системные зависимости ──
step 1 "Системные зависимости..."

# Проверяем ОС
if [ -f /etc/debian_version ]; then
    PACKAGES="cmake build-essential git python3-venv python3-pip curl"
    MISSING=""
    for pkg in $PACKAGES; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            MISSING="$MISSING $pkg"
        fi
    done
    if [ -n "$MISSING" ]; then
        echo "  Установка:$MISSING"
        $SUDO apt-get update -qq
        $SUDO apt-get install -y -qq $MISSING > /dev/null 2>&1
        ok "Пакеты установлены"
    else
        ok "Все пакеты уже есть"
    fi
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y -q cmake gcc gcc-c++ make git python3 python3-pip curl > /dev/null 2>&1
    ok "Пакеты установлены (RHEL/CentOS)"
else
    warn "Неизвестная ОС — убедитесь что установлены: cmake, g++, git, python3, pip"
fi

# ── 2. Python venv ──
step 2 "Python окружение..."

if [ ! -d "venv" ]; then
    python3 -m venv venv
    ok "venv создан"
else
    ok "venv уже существует"
fi

source venv/bin/activate
pip install -q --upgrade pip 2>/dev/null
pip install -q -r requirements.txt 2>/dev/null
ok "Зависимости установлены"

# ── 3. Собрать llama.cpp ──
step 3 "Сборка llama.cpp..."

if [ -f "llama-server" ]; then
    ok "llama-server уже собран"
else
    if [ ! -d "llama.cpp" ]; then
        echo "  Клонирование llama.cpp..."
        git clone --depth 1 https://github.com/ggml-org/llama.cpp 2>/dev/null
    fi

    cd llama.cpp

    # Определяем доступность CUDA
    CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release"
    if command -v nvcc &>/dev/null; then
        CMAKE_OPTS="$CMAKE_OPTS -DGGML_CUDA=ON"
        echo "  CUDA обнаружена — сборка с GPU"
    else
        CMAKE_OPTS="$CMAKE_OPTS -DGGML_CUDA=OFF"
        echo "  Сборка CPU-only"
    fi

    cmake -B build $CMAKE_OPTS > /dev/null 2>&1 || fail "cmake не удался"

    JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    echo "  Компиляция ($JOBS потоков)..."
    cmake --build build --config Release -j"$JOBS" > /dev/null 2>&1 || fail "Сборка llama.cpp не удалась"

    cp build/bin/llama-server ../
    cd ..
    ok "llama-server собран"
fi

# ── 4. Скачать модель ──
step 4 "Скачивание модели..."

mkdir -p models

HF_REPO=$(python3 -c "import yaml; c=yaml.safe_load(open('config/settings.yaml')); print(c['model']['hf_repo'])")
HF_FILE=$(python3 -c "import yaml; c=yaml.safe_load(open('config/settings.yaml')); print(c['model']['hf_file'])")

if [ -f "models/$HF_FILE" ]; then
    SIZE=$(du -h "models/$HF_FILE" | cut -f1)
    ok "Модель уже скачана: $HF_FILE ($SIZE)"
else
    echo "  Скачивание $HF_REPO/$HF_FILE ..."
    python3 -c "
from huggingface_hub import hf_hub_download
path = hf_hub_download('$HF_REPO', '$HF_FILE', local_dir='models/')
print(f'  Сохранено: {path}')
" || fail "Не удалось скачать модель. Проверьте интернет."
    ok "Модель скачана"
fi

# ── 5. Подготовить датасет для RAG ──
step 5 "RAG-датасет..."

mkdir -p data
RAG_ENABLED=$(python3 -c "import yaml; print(yaml.safe_load(open('config/settings.yaml'))['rag']['enabled'])")

if [ "$RAG_ENABLED" = "True" ] || [ "$RAG_ENABLED" = "true" ]; then
    if [ -f "data/tyv_rus_pairs.json" ]; then
        COUNT=$(python3 -c "import json; print(len(json.load(open('data/tyv_rus_pairs.json'))))")
        ok "Датасет готов: $COUNT пар"
    else
        echo "  Скачивание датасета..."
        "$SCRIPT_DIR/prepare_dataset.sh"
        ok "Датасет подготовлен"
    fi
else
    ok "RAG отключён в конфиге — датасет не нужен"
fi

# ── 6. Проверка ──
step 6 "Финальная проверка..."

ERRORS=0

[ -f "llama-server" ]      && ok "llama-server"    || { warn "llama-server не найден"; ERRORS=$((ERRORS+1)); }
[ -f "models/$HF_FILE" ]   && ok "Модель ($HF_FILE)" || { warn "Модель не найдена"; ERRORS=$((ERRORS+1)); }
[ -f "venv/bin/python" ]    && ok "Python venv"     || { warn "venv не создан"; ERRORS=$((ERRORS+1)); }
[ -f "server.py" ]          && ok "server.py"       || { warn "server.py не найден"; ERRORS=$((ERRORS+1)); }

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

if [ $ERRORS -eq 0 ]; then
    echo -e "  ${GREEN}Установка завершена!${NC}"
    echo ""
    echo "  Запуск:      ./scripts/start.sh"
    echo "  Стоп:        ./scripts/stop.sh"
    echo "  Тесты:       ./scripts/start.sh && python3 tests.py"
    echo "  Веб-чат:     http://localhost:8077"
    echo ""
    echo -e "  ${YELLOW}Быстрый старт:${NC}"
    echo "    ./scripts/start.sh && curl -s http://localhost:8077/translate \\"
    echo '      -H "Content-Type: application/json" \'
    echo '      -d '"'"'{"text":"Экии!","direction":"tyv2ru"}'"'"
else
    echo -e "  ${YELLOW}Установка завершена с предупреждениями ($ERRORS)${NC}"
    echo "  Исправьте проблемы и запустите install.sh повторно."
fi
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""
