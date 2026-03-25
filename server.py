"""
Тувинско-русский переводчик — FastAPI сервер с RAG.

Принимает запросы на перевод, ищет похожие пары из датасета,
подставляет их как примеры в промпт и отправляет в llama.cpp.
"""

import json
import os
import re
import time
from pathlib import Path

import numpy as np
import requests
import yaml
from fastapi import FastAPI, HTTPException
from fastapi.responses import RedirectResponse, HTMLResponse
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer

# ── Загрузка конфига ──

ROOT = Path(__file__).parent
with open(ROOT / "config" / "settings.yaml") as f:
    CFG = yaml.safe_load(f)

LLAMA_URL = f"http://127.0.0.1:{CFG['server']['llama_port']}/v1/chat/completions"

# ── RAG: загрузка датасета и эмбеддингов ──

pairs = []
embeddings = None
encoder = None

if CFG["rag"]["enabled"]:
    dataset_path = ROOT / CFG["rag"]["dataset"]
    cache_path = ROOT / CFG["rag"]["embeddings_cache"]

    if not dataset_path.exists():
        print(f"WARN: Датасет {dataset_path} не найден. RAG отключён.")
        print("      Запустите: ./scripts/prepare_dataset.sh")
        CFG["rag"]["enabled"] = False
    else:
        print("Загрузка датасета...")
        with open(dataset_path) as f:
            pairs = json.load(f)
        print(f"  {len(pairs):,} пар загружено")

        print(f"Загрузка модели эмбеддингов: {CFG['rag']['encoder_model']}...")
        encoder = SentenceTransformer(CFG["rag"]["encoder_model"])

        if cache_path.exists():
            print("  Загрузка кэша эмбеддингов...")
            embeddings = np.load(str(cache_path))
            if len(embeddings) != len(pairs):
                print("  Кэш устарел, пересчитываем...")
                embeddings = None

        if embeddings is None:
            print("  Вычисление эмбеддингов (первый запуск, ~5-10 мин)...")
            texts = [f"{p['tyv']} {p['ru']}" for p in pairs]
            embeddings = encoder.encode(
                texts, normalize_embeddings=True,
                show_progress_bar=True, batch_size=256,
            )
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            np.save(str(cache_path), embeddings)
            print(f"  Кэш сохранён: {cache_path}")

        print(f"RAG готов: {len(pairs):,} пар, top_k={CFG['rag']['top_k']}")


def find_similar(query: str, top_k: int = 5) -> list:
    """Поиск top_k похожих пар из датасета."""
    if not CFG["rag"]["enabled"] or encoder is None:
        return []
    q_emb = encoder.encode([query], normalize_embeddings=True)
    scores = (embeddings @ q_emb.T).flatten()
    top_idx = scores.argsort()[-top_k:][::-1]
    return [pairs[int(i)] for i in top_idx]


# ── FastAPI ──

app = FastAPI(title="Tyvan Translator", version="1.0.0")


class TranslateRequest(BaseModel):
    text: str
    direction: str = "tyv2ru"  # "tyv2ru" или "ru2tyv"
    rag_top_k: int | None = None  # переопределить кол-во RAG примеров


class TranslateResponse(BaseModel):
    translation: str
    direction: str
    time_ms: int
    rag_examples: int


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatMessage]
    temperature: float = 0.0
    max_tokens: int = 256


@app.get("/", response_class=HTMLResponse)
def root():
    """Веб-интерфейс переводчика."""
    return """<!DOCTYPE html>
<html lang="tyv">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Тыва-Орус очулга</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f7f7f5;color:#2c2c2a;min-height:100vh;display:flex;flex-direction:column}
.header{text-align:center;padding:2rem 1rem 1rem}
.header h1{font-size:1.6rem;font-weight:600;margin-bottom:.3rem}
.header p{font-size:.9rem;color:#888780}
.chat-wrap{flex:1;max-width:720px;width:100%;margin:0 auto;padding:0 1rem;overflow-y:auto}
.msg{margin:.75rem 0;display:flex;gap:.5rem}
.msg.user{justify-content:flex-end}
.msg.user .bubble{background:#e6f1fb;color:#0c447c;border-radius:16px 16px 4px 16px}
.msg.bot .bubble{background:#fff;color:#2c2c2a;border:1px solid #e8e6df;border-radius:16px 16px 16px 4px}
.bubble{max-width:80%;padding:.65rem 1rem;font-size:.95rem;line-height:1.5;word-break:break-word}
.meta{font-size:.7rem;color:#b4b2a9;margin-top:2px;padding:0 4px}
.msg.user .meta{text-align:right}
.input-wrap{max-width:720px;width:100%;margin:0 auto;padding:.75rem 1rem 1.25rem;position:sticky;bottom:0;background:#f7f7f5}
.input-box{display:flex;gap:.5rem;background:#fff;border:1px solid #d3d1c7;border-radius:16px;padding:.5rem .75rem;align-items:flex-end}
.input-box textarea{flex:1;border:none;outline:none;resize:none;font-size:.95rem;font-family:inherit;line-height:1.5;max-height:120px;background:transparent;color:#2c2c2a}
.input-box textarea::placeholder{color:#b4b2a9}
.send-btn{width:36px;height:36px;border-radius:50%;border:none;background:#2c2c2a;color:#fff;font-size:1.1rem;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0;transition:opacity .15s}
.send-btn:hover{opacity:.8}
.send-btn:disabled{opacity:.3;cursor:default}
.dir-toggle{display:flex;justify-content:center;gap:.5rem;margin:.5rem 0}
.dir-btn{padding:.35rem .9rem;border-radius:20px;border:1px solid #d3d1c7;background:#fff;font-size:.8rem;cursor:pointer;color:#5f5e5a;transition:all .15s}
.dir-btn.active{background:#2c2c2a;color:#fff;border-color:#2c2c2a}
.hint{text-align:center;font-size:.75rem;color:#b4b2a9;padding:.25rem 0 0}
.typing .bubble::after{content:'...';animation:dots 1s steps(3) infinite}
@keyframes dots{0%{content:'.'}33%{content:'..'}66%{content:'...'}}
@media(prefers-color-scheme:dark){
  body{background:#1a1a18;color:#d3d1c7}
  .header p{color:#888780}
  .msg.user .bubble{background:#1a3a5c;color:#b5d4f4}
  .msg.bot .bubble{background:#2c2c2a;color:#d3d1c7;border-color:#444441}
  .input-wrap{background:#1a1a18}
  .input-box{background:#2c2c2a;border-color:#444441}
  .input-box textarea{color:#d3d1c7}
  .send-btn{background:#d3d1c7;color:#1a1a18}
  .dir-btn{background:#2c2c2a;border-color:#444441;color:#b4b2a9}
  .dir-btn.active{background:#d3d1c7;color:#1a1a18;border-color:#d3d1c7}
}
</style>
</head>
<body>

<div class="header">
  <h1>Тыва-Орус очулга</h1>
  <p>Можете переводить с Тувинского на Русский и обратно</p>
</div>

<div class="dir-toggle">
  <button class="dir-btn active" data-dir="tyv2ru" onclick="setDir('tyv2ru')">Тыва → Орус</button>
  <button class="dir-btn" data-dir="ru2tyv" onclick="setDir('ru2tyv')">Орус → Тыва</button>
</div>

<div class="chat-wrap" id="chat"></div>

<div class="input-wrap">
  <div class="input-box">
    <textarea id="input" rows="1" placeholder="Бээр бижиңер..." onkeydown="onKey(event)" oninput="autoGrow(this)"></textarea>
    <button class="send-btn" id="sendBtn" onclick="send()">↑</button>
  </div>
  <p class="hint">Чорударда Enter базыптыңар, чаа одуруг кылырда Shift + Enter базыптыңар</p>
</div>

<script>
let dir = 'tyv2ru';
const chat = document.getElementById('chat');
const input = document.getElementById('input');
const sendBtn = document.getElementById('sendBtn');

function setDir(d) {
  dir = d;
  document.querySelectorAll('.dir-btn').forEach(b => {
    b.classList.toggle('active', b.dataset.dir === d);
  });
  input.focus();
}

function autoGrow(el) {
  el.style.height = 'auto';
  el.style.height = Math.min(el.scrollHeight, 120) + 'px';
  sendBtn.disabled = !el.value.trim();
}

function addMsg(text, role, meta) {
  const d = document.createElement('div');
  d.className = 'msg ' + role;
  let html = '<div class="bubble">' + esc(text) + '</div>';
  if (meta) html += '<div class="meta">' + meta + '</div>';
  d.innerHTML = html;
  chat.appendChild(d);
  chat.scrollTop = chat.scrollHeight;
  return d;
}

function esc(s) {
  const d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}

function onKey(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    send();
  }
}

async function send() {
  const text = input.value.trim();
  if (!text) return;
  input.value = '';
  input.style.height = 'auto';
  sendBtn.disabled = true;

  const arrow = dir === 'tyv2ru' ? 'тыва → орус' : 'орус → тыва';
  addMsg(text, 'user', arrow);

  const loader = addMsg('', 'bot typing', '');

  try {
    const r = await fetch('/translate', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({text, direction: dir})
    });
    const data = await r.json();
    loader.remove();
    const ms = data.time_ms || 0;
    const rag = data.rag_examples || 0;
    addMsg(data.translation, 'bot', ms + 'мс · ' + rag + ' RAG');
  } catch(e) {
    loader.remove();
    addMsg('Частырыг: ' + e.message, 'bot', '');
  }
  input.focus();
}

input.focus();
sendBtn.disabled = true;
</script>
</body>
</html>"""


@app.get("/health")
def health():
    """Проверка статуса."""
    return {
        "status": "ok",
        "model": CFG["model"]["hf_repo"],
        "rag_enabled": CFG["rag"]["enabled"],
        "rag_pairs": len(pairs),
    }


@app.post("/translate", response_model=TranslateResponse)
def translate(req: TranslateRequest):
    """Основной эндпоинт перевода с RAG."""
    t0 = time.time()

    top_k = req.rag_top_k or CFG["rag"]["top_k"]
    examples = find_similar(req.text, top_k=top_k)

    if req.direction == "tyv2ru":
        if examples:
            context = "\n".join(f"{e['tyv']} = {e['ru']}" for e in examples)
            prompt = f"Примеры переводов:\n{context}\n\nПереведи с тувинского на русский: {req.text}"
        else:
            prompt = f"Переведи с тувинского на русский: {req.text}"
    elif req.direction == "ru2tyv":
        if examples:
            context = "\n".join(f"{e['ru']} = {e['tyv']}" for e in examples)
            prompt = f"Примеры переводов:\n{context}\n\nПереведи с русского на тувинский: {req.text}"
        else:
            prompt = f"Переведи с русского на тувинский: {req.text}"
    else:
        raise HTTPException(400, "direction must be 'tyv2ru' or 'ru2tyv'")

    try:
        resp = requests.post(LLAMA_URL, json={
            "messages": [{"role": "user", "content": prompt}],
            "temperature": CFG["model"]["temp"],
            "max_tokens": CFG["model"]["max_tokens"],
            "stop": ["\n", "<end_of_turn>"],
        }, timeout=30)
        resp.raise_for_status()
        result = resp.json()["choices"][0]["message"]["content"].strip()
        result = re.sub(r'<[^>]+>', '', result).strip()
    except requests.exceptions.ConnectionError:
        raise HTTPException(503, "llama.cpp сервер не запущен")
    except Exception as e:
        raise HTTPException(500, f"Ошибка llama.cpp: {e}")

    elapsed = int((time.time() - t0) * 1000)

    return TranslateResponse(
        translation=result,
        direction=req.direction,
        time_ms=elapsed,
        rag_examples=len(examples),
    )


@app.post("/v1/chat/completions")
def chat_completions(req: ChatRequest):
    """OpenAI-совместимый эндпоинт (проксирует в llama.cpp с RAG)."""
    last_msg = req.messages[-1].content if req.messages else ""

    # Авто-детект направления из промпта
    direction = None
    text = last_msg
    if "с тувинского на русский:" in last_msg:
        direction = "tyv2ru"
        text = last_msg.split("на русский:")[-1].strip()
    elif "с русского на тувинский:" in last_msg:
        direction = "ru2tyv"
        text = last_msg.split("на тувинский:")[-1].strip()

    # Если это запрос на перевод — добавляем RAG
    if direction:
        examples = find_similar(text, top_k=CFG["rag"]["top_k"])
        if examples:
            if direction == "tyv2ru":
                context = "\n".join(f"{e['tyv']} = {e['ru']}" for e in examples)
            else:
                context = "\n".join(f"{e['ru']} = {e['tyv']}" for e in examples)
            enriched = f"Примеры переводов:\n{context}\n\n{last_msg}"
            req.messages[-1] = ChatMessage(role="user", content=enriched)

    # Проксируем в llama.cpp
    try:
        resp = requests.post(LLAMA_URL, json={
            "messages": [m.model_dump() for m in req.messages],
            "temperature": req.temperature,
            "max_tokens": req.max_tokens,
            "stop": ["\n", "<end_of_turn>"],
        }, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        # Чистим спецтокены из ответа
        if data.get("choices") and data["choices"][0].get("message"):
            content = data["choices"][0]["message"]["content"]
            data["choices"][0]["message"]["content"] = re.sub(r'<[^>]+>', '', content).strip()
        return data
    except requests.exceptions.ConnectionError:
        raise HTTPException(503, "llama.cpp сервер не запущен")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=CFG["server"]["host"], port=CFG["server"]["port"])
