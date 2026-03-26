#!/bin/bash
set -e

# ══════════════════════════════════════════════════════════════
#  Деплой тувинско-русского переводчика на сервер Aldan
#
#  Запуск в консоли Proxmox (контейнер 104):
#    curl -sSL https://raw.githubusercontent.com/Agisight/tyv2ru/main/scripts/deploy.sh | bash
#
#  Или вручную:
#    cd /opt/translator
#    git clone https://github.com/Agisight/tyv2ru.git
#    cd tyv2ru
#    ./scripts/deploy.sh
# ══════════════════════════════════════════════════════════════

# ── Цвета ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

INSTALL_PATH="/opt/translator/tyv2ru"

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Деплой тувинско-русского переводчика${NC}"
echo -e "${CYAN}  Сервер: Aldan / LXC 104${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""

# ── 1. Клонирование / обновление репо ──
echo -e "${CYAN}[1/4]${NC} Подготовка кода..."

if [ -d "$INSTALL_PATH/.git" ]; then
    cd "$INSTALL_PATH"
    git pull --ff-only 2>/dev/null && ok "Репозиторий обновлён" || warn "git pull не удался, используем текущую версию"
elif [ -d "$INSTALL_PATH" ]; then
    cd "$INSTALL_PATH"
    ok "Используем существующий $INSTALL_PATH"
else
    mkdir -p /opt/translator
    cd /opt/translator
    git clone https://github.com/Agisight/tyv2ru.git
    cd tyv2ru
    ok "Репозиторий склонирован"
fi

chmod +x scripts/*.sh 2>/dev/null || true

# ── 2. Установка (llama.cpp + модель + venv) ──
echo -e "\n${CYAN}[2/4]${NC} Установка..."
./scripts/install.sh

# ── 3. Создание systemd-сервисов ──
echo -e "\n${CYAN}[3/4]${NC} Настройка systemd..."

# Сервис llama.cpp
cat > /etc/systemd/system/tyv2ru-llama.service << SVCEOF
[Unit]
Description=Tyv2Ru — llama.cpp inference сервер
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_PATH
ExecStartPre=/bin/bash -c 'source venv/bin/activate && python3 -c "import yaml,os; c=yaml.safe_load(open(\"config/settings.yaml\")); print(\"Config OK\")"'
ExecStart=$INSTALL_PATH/llama-server \\
    -m $INSTALL_PATH/models/gemma-3-1b-it.Q4_K_M.gguf \\
    --host 127.0.0.1 \\
    --port 8078 \\
    --threads 4 \\
    --ctx-size 2048 \\
    --n-predict 64 \\
    --temp 0.0 \\
    --top-k 1 \\
    --repeat-penalty 1.3
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=tyv2ru-llama

[Install]
WantedBy=multi-user.target
SVCEOF
ok "tyv2ru-llama.service"

# Сервис FastAPI
cat > /etc/systemd/system/tyv2ru-api.service << SVCEOF
[Unit]
Description=Tyv2Ru — FastAPI переводчик
After=tyv2ru-llama.service
Requires=tyv2ru-llama.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_PATH
ExecStart=$INSTALL_PATH/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8077 --log-level warning
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=tyv2ru-api

[Install]
WantedBy=multi-user.target
SVCEOF
ok "tyv2ru-api.service"

# Перезагрузка и включение
systemctl daemon-reload
systemctl enable tyv2ru-llama tyv2ru-api
ok "Сервисы включены в автозагрузку"

# ── 4. Запуск и проверка ──
echo -e "\n${CYAN}[4/4]${NC} Запуск..."

# Останавливаем старый запуск через scripts/start.sh если был
"$INSTALL_PATH/scripts/stop.sh" 2>/dev/null || true

systemctl start tyv2ru-llama
echo -n "  Ожидание llama.cpp"
for i in $(seq 1 60); do
    if curl -s http://127.0.0.1:8078/health > /dev/null 2>&1; then
        echo -e " ${GREEN}готов!${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e " ${RED}таймаут!${NC}"
        echo "  journalctl -u tyv2ru-llama -n 20"
        exit 1
    fi
    echo -n "."
    sleep 1
done

systemctl start tyv2ru-api
sleep 2

# Проверка
echo ""
HEALTH=$(curl -s http://127.0.0.1:8077/health 2>/dev/null)
if echo "$HEALTH" | grep -q '"status"'; then
    ok "API работает!"
    echo "  $HEALTH"
else
    warn "API не отвечает, проверьте: journalctl -u tyv2ru-api -n 20"
fi

# Тест перевода
echo ""
echo "  Тест перевода..."
RESULT=$(curl -s http://127.0.0.1:8077/translate \
    -H "Content-Type: application/json" \
    -d '{"text":"Экии!","direction":"tyv2ru"}' 2>/dev/null)

if echo "$RESULT" | grep -q '"translation"'; then
    TRANSLATION=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['translation'])" 2>/dev/null)
    TIME_MS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['time_ms'])" 2>/dev/null)
    ok "Экии! → $TRANSLATION (${TIME_MS}мс)"
else
    warn "Перевод не сработал: $RESULT"
fi

# Определяем внешний IP
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Деплой завершён!${NC}"
echo ""
echo "  Веб-чат:     http://$SERVER_IP:8077"
echo "  API:         http://$SERVER_IP:8077/translate"
echo "  Здоровье:    http://$SERVER_IP:8077/health"
echo ""
echo "  Управление:"
echo "    systemctl status  tyv2ru-llama tyv2ru-api"
echo "    systemctl restart tyv2ru-llama tyv2ru-api"
echo "    journalctl -u tyv2ru-llama -f"
echo "    journalctl -u tyv2ru-api -f"
echo ""
echo "  Обновление:"
echo "    cd $INSTALL_PATH && git pull && make restart"
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""
