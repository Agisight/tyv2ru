# Тувинско-русский переводчик на базе Gemma 3

Автономный переводчик тувинского ↔ русского языка.
Работает на CPU без GPU, без интернета, без внешних API.

## Архитектура

```
Клиент (curl / Python / браузер)
        ↓
   FastAPI сервер (:8077)
        ↓
   RAG-поиск похожих пар (296K пар, ~10мс)
        ↓
   llama.cpp (:8078, внутренний)
        ↓
   Gemma 3 1B GGUF (~762 МБ)
```

## Быстрый старт

```bash
# 1. Клонировать
git clone https://github.com/Agisight/tyv2ru.git
cd tyv2ru

# 2. Установить
./scripts/install.sh

# 3. Запустить
./scripts/start.sh

# 4. Открыть в браузере
#    http://localhost:8077
```

## API

### Перевод (POST)

```bash
curl -s http://localhost:8077/translate \
  -H "Content-Type: application/json" \
  -d '{"text": "Экии!", "direction": "tyv2ru"}'
```

Ответ:
```json
{
  "translation": "Привет!",
  "direction": "tyv2ru",
  "time_ms": 150,
  "rag_examples": 5
}
```

### Направления
- `tyv2ru` — тувинский → русский (по умолчанию)
- `ru2tyv` — русский → тувинский

### OpenAI-совместимый (для интеграции)

```bash
curl -s http://localhost:8077/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Переведи с тувинского на русский: Экии!"}],
    "temperature": 0.0
  }'
```

### Веб-интерфейс (чат)

Откройте `http://localhost:8077` в браузере — встроенный чат для интерактивного перевода.

## Python-клиент

```python
from tyvan_client import TyvanTranslator

t = TyvanTranslator("http://localhost:8077")

print(t.translate("Экии!"))                        # → Привет!
print(t.translate("Семья", direction="ru2tyv"))     # → Өг-бүле
```

## Конфигурация

Все настройки в `config/settings.yaml`:

```yaml
model:
  path: models/gemma-3-1b-it.Q4_K_M.gguf
  threads: auto          # auto = все ядра
  ctx_size: 512
  temp: 0.0
  top_k: 1

rag:
  enabled: true
  top_k: 5               # сколько примеров подставлять
  dataset: data/tyv_rus_pairs.json

server:
  host: 0.0.0.0
  port: 8077
  llama_port: 8078       # внутренний порт llama.cpp
```

## Обновление модели

```bash
# Скачать новую версию с HuggingFace
./scripts/update_model.sh Agisight/gemma3-tyvan-1b-gguf-full

# Перезапустить
./scripts/restart.sh
```

## Структура проекта

```
tyv2ru/
├── README.md
├── config/
│   └── settings.yaml        # все настройки
├── scripts/
│   ├── install.sh            # установка зависимостей
│   ├── start.sh              # запуск всего
│   ├── stop.sh               # остановка
│   ├── restart.sh            # перезапуск
│   ├── update_model.sh       # обновление модели с HF
│   └── prepare_dataset.sh    # подготовка RAG-датасета
├── server.py                 # FastAPI сервер + RAG
├── tyvan_client.py           # Python-клиент
├── requirements.txt
├── data/                     # создаётся при install
│   └── tyv_rus_pairs.json
└── models/                   # создаётся при install
    └── gemma-3-1b-it.Q4_K_M.gguf
```

## Лицензия

Модель Gemma 3 распространяется под [Gemma Terms of Use](https://ai.google.dev/gemma/terms).
Датасет [Agisight/tyv-rus-200k](https://huggingface.co/datasets/Agisight/tyv-rus-200k).
