#!/bin/bash
set -e

# ── Обновление модели с HuggingFace ──
# Использование:
#   ./scripts/update_model.sh                              # из конфига
#   ./scripts/update_model.sh Agisight/gemma3-tyvan-1b-gguf-full  # конкретный repo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

source venv/bin/activate 2>/dev/null || true

# Определяем repo
if [ -n "$1" ]; then
    HF_REPO="$1"
else
    HF_REPO=$(python3 -c "import yaml; print(yaml.safe_load(open('config/settings.yaml'))['model']['hf_repo'])")
fi

HF_FILE=$(python3 -c "import yaml; print(yaml.safe_load(open('config/settings.yaml'))['model']['hf_file'])")

echo "Обновление модели..."
echo "  Repo: $HF_REPO"
echo "  Файл: $HF_FILE"

# Бэкап текущей модели
if [ -f "models/$HF_FILE" ]; then
    echo "  Бэкап: models/${HF_FILE}.bak"
    cp "models/$HF_FILE" "models/${HF_FILE}.bak"
fi

# Скачивание
echo "  Скачивание..."
huggingface-cli download "$HF_REPO" "$HF_FILE" --local-dir models/

echo ""
echo "Модель обновлена!"
echo ""

# Обновить repo в конфиге
python3 -c "
import yaml
with open('config/settings.yaml') as f:
    cfg = yaml.safe_load(f)
cfg['model']['hf_repo'] = '$HF_REPO'
with open('config/settings.yaml', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, allow_unicode=True)
print('  Конфиг обновлён')
"

echo "Перезапуск: ./scripts/restart.sh"
