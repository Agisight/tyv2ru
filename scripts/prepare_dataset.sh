#!/bin/bash
set -e

# ── Подготовка RAG-датасета из HuggingFace ──

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

source venv/bin/activate 2>/dev/null || true

echo "Скачивание датасета Agisight/tyv-rus-200k..."

python3 -c "
from datasets import load_dataset
import json, yaml

with open('config/settings.yaml') as f:
    cfg = yaml.safe_load(f)

ds_name = cfg['rag']['hf_dataset']
print(f'  Загрузка {ds_name}...')
ds = load_dataset(ds_name, split='train')

pairs = []
for r in ds:
    tyv = (r.get('tyv') or '').strip()
    ru = (r.get('ru') or '').strip()
    if tyv and ru:
        pairs.append({'tyv': tyv, 'ru': ru})

output = cfg['rag']['dataset']
with open(output, 'w') as f:
    json.dump(pairs, f, ensure_ascii=False)

print(f'  Сохранено {len(pairs):,} пар в {output}')
"

echo "Датасет готов!"
