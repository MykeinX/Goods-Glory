# AGENTS.md

Behavioral guidelines to reduce common LLM coding mistakes. 
Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. 
For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them. Don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" 
If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it. Don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. 
Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, 
fewer rewrites due to overcomplication, and clarifying questions come 
before implementation rather than after mistakes.

## Imported Claude Cowork project instructions

iPhone logistics simulation game

## 5. Proje belgeleri — az oku

Varsayılan bağlam:

1. `VISION.md` — ürün vizyonu
2. `Goods&Glory/ARCHITECTURE.md` — katmanlar, dosya düzeni, nereye bakılır
3. İlgili kod / JSON — uygulama gerçeği
4. `OPEN.md` — yalnız yön belirsizse

Mikro karar, eski GDD, plan taslağı veya karar günlüğü aranmaz / üretilmez.
Davranış ayrıntısı kodda yaşar.

## 6. Kod Düzeni — Tekrar ve Şişme Yasağı

**Bakımı kolay, modüler, tekrarlamayan, data-driven kod. MVVM ve dosya bölmesi sürer.**

- **Dosya ~400 satırda bölünür, 700 üst sınır.** Klasör açmak bölmek değildir.
  Yeni bir tip yazıyorsan ve tek bir ekranın iç detayı değilse kendi dosyasına
  gider; bir alt bileşen ikinci kez kullanıldığı anda kendi dosyasına taşınır.
  Motor extension’ları (`SimulationEngine+…`) tek dosyaya sıkıştırılmaz.
- **Aynı hesabı/bileşeni ikinci kez yazma.** İki kopya zamanla ayrışır ve tek
  bir değişiklik birden çok yeri düzeltmeyi gerektirir. Ortak yerler:
  `Domain` (kural/hesap), `Format` (biçim), `SessionDisplay` (katalog aramaları),
  `DesignSystem` (görsel bileşen), `<Tip>Display` (domain tipinin sunumu).
- **Hesap Domain'de, görüntü Presentation'da.** Bir sayı birden çok ekranda
  görünüyorsa onu motor hesaplar; view yalnız okur.

Ayrıntı: `Goods&Glory/ARCHITECTURE.md`.