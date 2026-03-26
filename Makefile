# ── Тувинско-русский переводчик ──
# make install  — установить всё (llama.cpp, модель, зависимости)
# make start    — запустить сервер
# make stop     — остановить
# make restart  — перезапустить
# make test     — запустить тесты
# make status   — проверить здоровье
# make logs     — смотреть логи

.PHONY: install start stop restart test status logs update clean

install:
	@chmod +x scripts/*.sh
	@./scripts/install.sh

start:
	@chmod +x scripts/*.sh
	@./scripts/start.sh

stop:
	@./scripts/stop.sh

restart:
	@./scripts/restart.sh

test:
	@. venv/bin/activate && python3 tests.py

status:
	@curl -s http://localhost:8077/health 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "Сервер не запущен. Запустите: make start"

logs:
	@tail -f logs/llama.log logs/server.log

update:
	@./scripts/update_model.sh

clean:
	@./scripts/stop.sh 2>/dev/null || true
	@rm -rf llama.cpp venv logs models data .llama.pid .server.pid llama-server
	@echo "Очищено. Для переустановки: make install"
