"""
Клиент тувинско-русского переводчика.

Использование:
    from tyvan_client import TyvanTranslator
    t = TyvanTranslator("http://localhost:8077")
    print(t.translate("Экии!"))
    print(t.translate("Семья", direction="ru2tyv"))
"""

import requests
import time


class TyvanTranslator:
    def __init__(self, base_url: str = "http://localhost:8077"):
        self.base_url = base_url.rstrip("/")

    def translate(self, text: str, direction: str = "tyv2ru") -> str:
        """Перевод текста. Возвращает строку."""
        r = self.translate_full(text, direction)
        return r["translation"]

    def translate_full(self, text: str, direction: str = "tyv2ru") -> dict:
        """Перевод с метаданными (время, кол-во RAG примеров)."""
        resp = requests.post(f"{self.base_url}/translate", json={
            "text": text,
            "direction": direction,
        }, timeout=30)
        resp.raise_for_status()
        return resp.json()

    def health(self) -> dict:
        """Проверка статуса сервера."""
        resp = requests.get(f"{self.base_url}/health", timeout=5)
        resp.raise_for_status()
        return resp.json()


if __name__ == "__main__":
    t = TyvanTranslator()

    print("=== Статус ===")
    print(t.health())
    print()

    print("=== Тувинский → Русский ===")
    for text in ["Экии!", "Мен Тывада чурттап турар мен.", "Четтирдим."]:
        r = t.translate_full(text, "tyv2ru")
        print(f"  {text} → {r['translation']} ({r['time_ms']}мс, {r['rag_examples']} примеров)")
    print()

    print("=== Русский → Тувинский ===")
    for text in ["Привет!", "Семья", "Спасибо", "До свидания"]:
        r = t.translate_full(text, "ru2tyv")
        print(f"  {text} → {r['translation']} ({r['time_ms']}мс, {r['rag_examples']} примеров)")
