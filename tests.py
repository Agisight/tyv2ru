#!/usr/bin/env python3
"""
Тест-кейсы для тувинско-русского переводчика.

Запуск:
    python3 tests.py                    # все тесты
    python3 tests.py --url http://host:8077  # другой сервер
    python3 tests.py --verbose          # подробный вывод
"""

import argparse
import json
import sys
import time

import requests

# ── Тест-кейсы ──
# Формат: (текст, направление, ожидаемые_варианты или None если просто проверяем что ответ есть)

TEST_CASES = [
    # === Приветствия ===
    ("Экии!", "tyv2ru", ["Привет", "Здравствуй"]),
    ("Привет!", "ru2tyv", ["Экии"]),

    # === Простые слова ===
    ("даарта", "tyv2ru", ["завтра"]),
    ("завтра", "ru2tyv", ["даарта"]),
    ("ном", "tyv2ru", ["книга"]),
    ("книга", "ru2tyv", ["ном"]),
    ("суг", "tyv2ru", ["вода"]),
    ("вода", "ru2tyv", ["суг"]),

    # === Фразы ===
    ("Мен Тывада чурттап турар мен.", "tyv2ru", ["живу", "Тыва", "Тува"]),
    ("Четтирдим.", "tyv2ru", ["Спасибо", "Благодар"]),
    ("Спасибо", "ru2tyv", ["Четтирдим"]),

    # === Вопросы ===
    ("Силерниң адыңар кымыл?", "tyv2ru", ["имя", "зовут", "как"]),
    ("Как вас зовут?", "ru2tyv", None),

    # === Длинные предложения ===
    ("Бөгүн агаар-бойдус чылыг-дыр.", "tyv2ru", ["погода", "тепл"]),
    ("Сегодня хорошая погода.", "ru2tyv", None),

    # === Пустые и edge-cases ===
    ("До свидания!", "ru2tyv", None),
    ("Доброе утро!", "ru2tyv", None),
]


def test_health(base_url: str) -> bool:
    """Проверка что сервер работает."""
    try:
        r = requests.get(f"{base_url}/health", timeout=5)
        r.raise_for_status()
        data = r.json()
        print(f"  Статус:  {data.get('status', '?')}")
        print(f"  Модель:  {data.get('model', '?')}")
        print(f"  RAG:     {data.get('rag_enabled', '?')} ({data.get('rag_pairs', 0):,} пар)")
        return True
    except Exception as e:
        print(f"  ОШИБКА: {e}")
        return False


def test_translate(base_url: str, text: str, direction: str,
                   expected: list | None, verbose: bool) -> dict:
    """Один тест перевода. Возвращает результат."""
    arrow = "tyv→ru" if direction == "tyv2ru" else "ru→tyv"

    try:
        t0 = time.time()
        r = requests.post(f"{base_url}/translate", json={
            "text": text,
            "direction": direction,
        }, timeout=30)
        elapsed = int((time.time() - t0) * 1000)
        r.raise_for_status()
        data = r.json()
    except Exception as e:
        return {"status": "ERROR", "text": text, "error": str(e)}

    translation = data.get("translation", "")
    rag_count = data.get("rag_examples", 0)

    # Проверка результата
    if expected is None:
        # Просто проверяем что ответ непустой
        passed = len(translation.strip()) > 0
    else:
        # Проверяем что хотя бы одно ожидаемое слово есть в ответе
        translation_lower = translation.lower()
        passed = any(exp.lower() in translation_lower for exp in expected)

    status = "PASS" if passed else "FAIL"
    icon = "✓" if passed else "✗"

    if verbose or not passed:
        print(f"  {icon} [{arrow}] {text}")
        print(f"    → {translation}  ({elapsed}мс, {rag_count} RAG)")
        if not passed and expected:
            print(f"    Ожидалось: {expected}")
    else:
        print(f"  {icon} [{arrow}] {text} → {translation}  ({elapsed}мс)")

    return {
        "status": status,
        "text": text,
        "direction": direction,
        "translation": translation,
        "time_ms": elapsed,
        "rag_examples": rag_count,
        "expected": expected,
    }


def test_openai_compat(base_url: str) -> bool:
    """Проверка OpenAI-совместимого эндпоинта."""
    try:
        r = requests.post(f"{base_url}/v1/chat/completions", json={
            "messages": [
                {"role": "user", "content": "Переведи с тувинского на русский: Экии!"}
            ],
            "temperature": 0.0,
            "max_tokens": 64,
        }, timeout=30)
        r.raise_for_status()
        data = r.json()
        content = data["choices"][0]["message"]["content"]
        passed = len(content.strip()) > 0
        icon = "✓" if passed else "✗"
        print(f"  {icon} OpenAI /v1/chat/completions → {content.strip()}")
        return passed
    except Exception as e:
        print(f"  ✗ OpenAI /v1/chat/completions → ОШИБКА: {e}")
        return False


def test_response_time(base_url: str, max_ms: int = 5000) -> bool:
    """Проверка что ответ приходит быстрее max_ms."""
    try:
        t0 = time.time()
        r = requests.post(f"{base_url}/translate", json={
            "text": "Экии!",
            "direction": "tyv2ru",
        }, timeout=30)
        elapsed = int((time.time() - t0) * 1000)
        passed = elapsed < max_ms
        icon = "✓" if passed else "✗"
        print(f"  {icon} Время ответа: {elapsed}мс (лимит: {max_ms}мс)")
        return passed
    except Exception as e:
        print(f"  ✗ Время ответа: ОШИБКА: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Тесты переводчика")
    parser.add_argument("--url", default="http://localhost:8077", help="URL сервера")
    parser.add_argument("--verbose", "-v", action="store_true", help="Подробный вывод")
    parser.add_argument("--max-time", type=int, default=5000, help="Макс. время ответа (мс)")
    parser.add_argument("--json", action="store_true", help="Вывод в JSON")
    args = parser.parse_args()

    print("══════════════════════════════════════════")
    print("  Тесты тувинско-русского переводчика")
    print(f"  Сервер: {args.url}")
    print("══════════════════════════════════════════")
    print()

    results = []
    total_pass = 0
    total_fail = 0
    total_error = 0

    # ── 1. Health check ──
    print("─── Health Check ───")
    if not test_health(args.url):
        print("\nСервер недоступен. Запустите: ./scripts/start.sh")
        sys.exit(1)
    print()

    # ── 2. Тесты перевода ──
    print("─── Переводы ───")
    for text, direction, expected in TEST_CASES:
        result = test_translate(args.url, text, direction, expected, args.verbose)
        results.append(result)
        if result["status"] == "PASS":
            total_pass += 1
        elif result["status"] == "FAIL":
            total_fail += 1
        else:
            total_error += 1
    print()

    # ── 3. OpenAI-совместимость ──
    print("─── OpenAI API ───")
    if test_openai_compat(args.url):
        total_pass += 1
    else:
        total_fail += 1
    print()

    # ── 4. Скорость ──
    print("─── Скорость ───")
    if test_response_time(args.url, args.max_time):
        total_pass += 1
    else:
        total_fail += 1
    print()

    # ── Итоги ──
    total = total_pass + total_fail + total_error
    print("══════════════════════════════════════════")
    print(f"  Результат: {total_pass}/{total} пройдено")
    if total_fail:
        print(f"  Провалено: {total_fail}")
    if total_error:
        print(f"  Ошибки:    {total_error}")

    # Среднее время
    times = [r["time_ms"] for r in results if "time_ms" in r]
    if times:
        print(f"  Среднее время: {sum(times) // len(times)}мс")
        print(f"  Макс. время:   {max(times)}мс")
    print("══════════════════════════════════════════")

    # JSON-вывод
    if args.json:
        report = {
            "server": args.url,
            "total": total,
            "passed": total_pass,
            "failed": total_fail,
            "errors": total_error,
            "avg_time_ms": sum(times) // len(times) if times else 0,
            "results": results,
        }
        with open("test_results.json", "w") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        print(f"\nОтчёт сохранён: test_results.json")

    sys.exit(0 if total_fail == 0 and total_error == 0 else 1)


if __name__ == "__main__":
    main()
