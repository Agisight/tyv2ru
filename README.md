# Тувинско-русский переводчик на базе Gemma 3

Автономный переводчик тувинского ↔ русского языка.
Работает на CPU без GPU, без интернета, без внешних API.

## Установка и запуск — одна команда

```bash
git clone https://github.com/Agisight/tyv2ru.git && cd tyv2ru && make start
```

Скрипт автоматически:
1. Установит системные зависимости (cmake, g++, python3)
2. Создаст Python venv и установит пакеты
3. Склонирует и соберёт llama.cpp
4. Скачает GGUF-модель с HuggingFace (~762 МБ)
5. Запустит llama.cpp + FastAPI сервер

После завершения откройте **http://localhost:8077** — встроенный чат для перевода.

### Требования

- **ОС:** Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- **RAM:** 2 ГБ минимум
- **CPU:** 2+ ядра
- **Диск:** 3 ГБ (llama.cpp + модель)
- **GPU:** не нужен (но будет использован если есть CUDA)

### Управление

```bash
make start     # Запуск (+ автоустановка при первом запуске)
make stop      # Остановка
make restart   # Перезапуск
make test      # Прогнать тесты
make status    # Проверить здоровье
make logs      # Смотреть логи
make update    # Обновить модель с HuggingFace
make clean     # Удалить всё (модель, venv, llama.cpp)
```

## Архитектура

```
Клиент (curl / Python / браузер)
        ↓
   FastAPI сервер (:8077)
        ↓
   RAG-поиск похожих пар (~10мс)
        ↓
   llama.cpp (:8078, внутренний)
        ↓
   Gemma 3 1B GGUF (~762 МБ)
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
  path: models/gemma3-tyvan-merged-17k.Q4_K_M.gguf
  hf_repo: Agisight/gemma3-tyvan-1b-gguf-17k
  threads: auto          # auto = все ядра
  ctx_size: 2048
  temp: 0.0
  top_k: 1

rag:
  enabled: false
  top_k: 3
  dataset: data/tyv_rus_pairs.json

server:
  host: 0.0.0.0
  port: 8077
  llama_port: 8078       # внутренний порт llama.cpp
```

## Обновление модели

```bash
make update                                                    # из конфига
./scripts/update_model.sh Agisight/gemma3-tyvan-1b-gguf-full   # конкретный repo
make restart
```

## Структура проекта

```
tyv2ru/
├── Makefile                  # make start/stop/test/...
├── README.md
├── config/
│   └── settings.yaml        # все настройки
├── scripts/
│   ├── install.sh            # установка всего
│   ├── start.sh              # запуск (с автоустановкой)
│   ├── stop.sh               # остановка
│   ├── restart.sh            # перезапуск
│   ├── update_model.sh       # обновление модели с HF
│   └── prepare_dataset.sh    # подготовка RAG-датасета
├── server.py                 # FastAPI сервер + RAG
├── tyvan_client.py           # Python-клиент
├── tests.py                  # тест-кейсы
├── requirements.txt
├── data/                     # создаётся при install
│   └── tyv_rus_pairs.json
└── models/                   # создаётся при install
    └── *.gguf
```

## Лицензия

Модель Gemma 3 распространяется под [Gemma Terms of Use](https://ai.google.dev/gemma/terms).
Датасет [Agisight/tyv-rus-200k](https://huggingface.co/datasets/Agisight/tyv-rus-200k).
