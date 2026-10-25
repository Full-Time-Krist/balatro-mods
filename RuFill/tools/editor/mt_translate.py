#!/usr/bin/env python3
"""Machine-translate untranslated chunk lines with a free LLM (text.pollinations.ai, no key).

Writes into the editor's translations.json (entries get "mt": true so they can be found
and reviewed later), then the usual build() turns them into ru.lua.
Free tier: one reply per 30 s per IP, so batches go one after another.
Usage: mt_translate.py [--build] [--limit N]
"""
import argparse
import json
import re
import sys
import time
import urllib.request

import rufill_editor as r

URL = "https://text.pollinations.ai/openai"
MODEL = "openai-fast"

PROMPT = """You translate UI text of Balatro (a poker roguelike card game) mods from English into Russian.
Rules:
- Keep EVERY formatting token exactly as is and in the same order: {C:mult}, {X:mult,C:white}, {}, {s:0.8}, #1#, #2#, [[...]], \\n, %s.
- Do not translate text inside {...} and #...#.
- Glossary (vanilla Russian Balatro): Mult = множ., Chips = фишки, Joker = джокер (never "жокер"), hand = рука, played hand = разыгранная рука,
  poker hand = покерная рука, discard = сброс, Blind = блайнд, Boss Blind = босс-блайнд, Small/Big Blind = малый/большой блайнд,
  Ante = анте, Tarot = Таро, Planet = планета, Spectral = спектральная карта, Voucher = ваучер, Tag = тег, Booster Pack = бустер,
  Consumable = расходник, Enhancement = улучшение, Edition = издание, Foil = фольга, Holographic = голографический,
  Polychrome = полихромный, Negative = негативный, Seal = печать, Sticker = наклейка, Eternal = вечный, Perishable = скоропортящийся,
  Rental = арендованный, scoring card = засчитанная карта, held in hand = в руке, face card = карта с лицом, Rare = редкий,
  Uncommon = необычный, Common = обычный, Legendary = легендарный, reroll = перебросить, sell value = цена продажи, $ stays $,
  Spade(s) = пики, Heart(s) = червы, Club(s) = трефы, Diamond(s) = бубны, suit = масть, rank = достоинство,
  Ace = туз, King = король, Queen = дама, Jack = валет, Stone Card = каменная карта, Steel = стальная, Gold Card = золотая карта,
  Glass = стеклянная, Wild Card = дикая карта, Lucky = счастливая, Bonus = бонусная, Mult Card = карта множ.,
  "Ante" is indeclinable (на анте 3, в анте), Art Credit = автор арта, Halves = уменьшается вдвое (verb), Retrigger = повторно запускает,
  Level up = повышает уровень, Joker slot = слот джокера, hand size = размер руки, score = счёт, Blind requirement = требование блайнда.
- Unknown made-up words, mod names and card names in {C:...} highlighting may stay in English if unsure.
- Proper names of cards/characters: translate if they are ordinary words, otherwise transliterate or keep.
- Lines are fragments of one card description shown line by line; keep each line short, roughly as long as the English.
- Answer ONLY with a JSON object mapping the same ids to Russian strings. No comments."""

TOKEN = re.compile(r"\{[^}]*\}|#\d+#|\[\[[^\]]*\]\]|%[sd]")


def tokens(s):
    return TOKEN.findall(s)


def ask(items):
    body = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": PROMPT},
            {"role": "user", "content": json.dumps(items, ensure_ascii=False)},
        ],
        "reasoning_effort": "low",
    }
    req = urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.load(resp)
    text = data["choices"][0]["message"]["content"].strip()
    text = re.sub(r"^```(json)?|```$", "", text).strip()
    try:
        return json.loads(text)
    except ValueError:  # the model sometimes breaks a quote; take the pairs that survived
        pairs = re.findall(r'"(\d+)"\s*:\s*"((?:[^"\\]|\\.)*)"', text)
        if not pairs:
            raise
        return {k: json.loads('"' + v + '"') for k, v in pairs}


last = 0


def translate_batch(batch):
    """batch: [(key, header, rel, en)] -> {key: ru}; retries, validates tokens."""
    items = {str(i): en for i, (_, _, _, en) in enumerate(batch)}
    global last
    for attempt in range(6):
        time.sleep(max(0, last + 31 - time.time()))
        try:
            res = ask(items)
            last = time.time()
            break
        except Exception as e:  # network, rate limit, bad JSON
            last = time.time()
            err = e
    else:
        print(f"batch failed: {err}", file=sys.stderr)
        return {}
    out = {}
    for i, (key, _, _, en) in enumerate(batch):
        ru = res.get(str(i))
        if not isinstance(ru, str) or not ru.strip():
            continue
        if sorted(tokens(ru)) != sorted(tokens(en)) or not r.CYRILLIC.search(ru):
            continue
        out[key] = ru.strip()
    return out


def pending(tr):
    todo = []
    for path in r.chunk_files():
        for header, lines in r.parse_chunk(path):
            for rel, text in lines:
                key = f"{header}|{rel}"
                if r.needs_translation(text) and not tr.get(key, {}).get("ru"):
                    todo.append((key, header, rel, r._unesc(text)))
    return todo


def batches(todo, size=45):
    """Keep one entry's lines together so the model sees the whole card."""
    cur, head = [], None
    for item in todo:
        if len(cur) >= size and item[1] != head:
            yield cur
            cur = []
        cur.append(item)
        head = item[1]
    if cur:
        yield cur


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--build", action="store_true")
    a = ap.parse_args()
    tr = r.load_translations()
    todo = pending(tr)
    if a.limit:
        todo = todo[: a.limit]
    bl = list(batches(todo))
    print(f"lines: {len(todo)}, batches: {len(bl)}", flush=True)
    done = 0
    for n, batch in enumerate(bl, 1):
        res = translate_batch(batch)
        tr = r.load_translations()
        for key, _, _, en in batch:
            if key in res:
                tr[key] = {"en": en, "ru": r._esc(res[key]), "mt": True}
        r.save_translations(tr)
        done += len(res)
        print(f"[{n}/{len(bl)}] +{len(res)}/{len(batch)} total {done}", flush=True)
    if a.build:
        print(r.build())


if __name__ == "__main__":
    main()
