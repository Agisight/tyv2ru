# Документация инфраструктуры

## Сервер Aldan

| Параметр | Значение |
|----------|----------|
| Хост | Proxmox 9.0.10 |
| IP (внешний) | <YOUR_SERVER_IP> |
| Proxmox UI | https://<YOUR_SERVER_IP>:8006 |
| Контейнер | LXC 104 «translator» |
| IP (внутренний) | 10.10.10.50 |
| ОС | Ubuntu |
| CPU | 4 ядра |
| RAM | 10 ГБ |
| Диск | 49 ГБ |
| GPU | нет |

## Сервисы в контейнере 104

| Сервис | Порт | Описание |
|--------|------|----------|
| `translator.service` | — | NLLB переводчик (существующий) |
| `tyv2ru-llama.service` | 8078 (внутренний) | llama.cpp inference |
| `tyv2ru-api.service` | 8077 | FastAPI + веб-чат |

## Доступ

- **Веб-чат:** http://<YOUR_SERVER_IP>:8077
- **API:** http://<YOUR_SERVER_IP>:8077/translate
- **Proxmox:** https://<YOUR_SERVER_IP>:8006 → Контейнер 104 → Console

## Управление

```bash
# Статус
systemctl status tyv2ru-llama tyv2ru-api

# Перезапуск
systemctl restart tyv2ru-llama tyv2ru-api

# Логи
journalctl -u tyv2ru-llama -f
journalctl -u tyv2ru-api -f

# Обновление кода + модели
cd /opt/translator/tyv2ru
git pull
make restart
```

## Деплой с нуля

Открыть консоль контейнера 104 в Proxmox и выполнить:

```bash
cd /opt/translator && git clone https://github.com/Agisight/tyv2ru.git && cd tyv2ru && ./scripts/deploy.sh
```

Скрипт сделает всё автоматически: установит зависимости, соберёт llama.cpp, скачает модель, создаст systemd-сервисы, запустит и проверит.
