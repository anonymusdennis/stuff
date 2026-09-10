# AI text maintenance tool with review popup

New tool for the `ZZWN00224895_AI` framework: the assistant reads the texts of a
program text pool or a message class, proposes new / changed / deleted / translated
texts, and the user reviews every proposal in a modeless HTML popup while the
assistant keeps working ("coop mode"). Nothing is written without a click.

## Objects

| Object | Type | Purpose |
|---|---|---|
| `ZZWN00224895_AI_TEXTS_API` | class | Backend: read/write text pools (`READ/INSERT TEXTPOOL`) and T100 in any installed language, language resolution (ISO ↔ SAP key), length limits, `ENQUEUE_ESRDIRE`, transport popup (`TR_REQUEST_CHOICE` + `TR_OBJECTS_INSERT`). Owns the shared types. |
| `ZZWN00224895_AI_TEXTS_HTML` | class | Renders the review page (dark theme, per-row buttons, inline forms, language toggles, filter). |
| `ZZWN00224895_AI_TEXTS_REVIEW` | class | Singleton review model + popup controller (`CL_GUI_DIALOGBOX_CONTAINER` + `CL_GUI_HTML_VIEWER`), SAPEVENT handling, decisions, apply, AI feedback queue. |
| `ZZWN00224895_AI_TOOL_TEXTS` | class | Implements `ZZWN00224895_AI_IF_TOOL`; sub-tools `text_list`, `text_suggest`, `text_review_status`. Discovered automatically by the registry. |
| `zzwn00224895_ai_cimp.extension.abap` | snippet | Three insertions into report `ZZWN00224895_AI` (CDEF/CIMP): PAI hook, idle delivery of user requests, cleanup on BACK. |
| `system_prompt_text_maintenance.txt` | text | System / additional prompt for the text maintenance task. |

Activation order: `API` → `HTML` → `REVIEW` → `TOOL`, then apply the report extension.
All classes are `FINAL`, `CREATE PUBLIC` (`REVIEW` is `CREATE PRIVATE`, use `=>get( )`).

## How it works

```
model ── text_list ──────────▶ TOOL ──▶ REVIEW.load_object ──▶ API.read_all_languages
model ── text_suggest ───────▶ TOOL ──▶ validate (object, key, language, length)
                                        ──▶ REVIEW.add_suggestion ──▶ popup refresh (#anchor)
user  ── click in popup ─────▶ REVIEW.on_sapevent ──▶ state change + repaint
                               (apply / close) ──▶ pending ──▶ lcl_app.pai_0100 ──▶ REVIEW.process_pending
user  ── Retry / Changes / Deny ──▶ feedback queue ──▶ next text_* tool result   (turn running)
                                                    ──▶ lcl_app.deliver_text_review ──▶ user message (idle)
model ── text_review_status ─▶ TOOL ──▶ decisions + open requests
```

### Popup

* Grouped by object → text (kind, key, defined length / maximum) → original texts in the
  selected languages → all suggestions for that text (any language, any number of versions).
* Per suggestion: **Accept**, **Accept & apply**, **Retry** (AI is asked for a different
  text), **Request changes** (inline comment → AI), **Deny with reason** (inline comment →
  AI), **Refuse** (silent, AI is not informed), **Undo**.
* Header/footer: **Accept all pending**, **Apply accepted**, **Import: accept & apply all**,
  **Close** (asks for confirmation when suggestions are not applied yet; discarded ones are
  marked refused).
* Language toggles for the original texts (per ISO code; `all` / `master only` / `none`).
* Filter box (JavaScript, optional) filters by object, key, text, language or `#id`.
* Status banner for results / errors; "AI ... n s ago" shows the assistant's last activity.
* The list grows while the assistant calls `text_suggest`; the newest row is scrolled into view.

### Writes

* Grouped per object and language: one `READ TEXTPOOL` → patch → `INSERT TEXTPOOL ... STATE 'A'`
  (or `DELETE TEXTPOOL` when the language becomes empty). Messages: `MODIFY t100` / `DELETE FROM t100`
  plus `T100U`.
* Program lock via `ENQUEUE_ESRDIRE`. When the object's package is not local, Apply
  opens the standard CTS request popup (`TR_REQUEST_CHOICE`) and records
  `LIMU REPT` (program texts) or `LIMU MESS` / `R3TR MSAG` (messages) with
  `TR_OBJECTS_INSERT`. The chosen request is reused for later writes in the same session.
* Selection texts keep their 8-character flag prefix; a Dictionary reference (`D`) is dropped
  when an own text is supplied.
* Text symbols: a longer defined length (`new_length`) is written to the target language row and,
  if smaller, to the master language row as well.
* Failed writes mark the row **apply failed** with the reason; the user can retry.

### Length rules enforced before a suggestion is accepted

| Kind | Limit |
|---|---|
| Text symbol (I) | defined length of the symbol; the model may raise it with `new_length` (≤ 132) |
| Selection text (S) | 30 |
| Program title (R) / list title (T) | 70 |
| List heading (H) | 132 |
| Message (M) | 73 |

A violation is returned to the model as an actionable error (shorten, or repeat with `new_length`).

## Report extension (required)

`zzwn00224895_ai_cimp.extension.abap` documents the three insertions:

1. `lcl_app` gets `METHODS deliver_text_review.`
2. `pai_0100`: on `BACK/EXIT/CANC` call `zzwn00224895_ai_texts_review=>get( )->close( )`;
   in `WHEN OTHERS` after `process_pending( )` call
   `zzwn00224895_ai_texts_review=>get( )->process_pending( )` and `deliver_text_review( )`.
3. `on_timer`, "turn finished" branch: call `deliver_text_review( )` before `refresh_html( )`.

Without the hook the popup still opens and records decisions, but *apply* and *close* (which
need dialogs) are not executed and idle-time delivery of user requests does not happen.

## Batch / background

`ZZWN00224895_AI_TEXTS_REVIEW=>UI_AVAILABLE` is false in background jobs; suggestions are then
recorded only and the tool result says so. Do not activate the tool for the batch report.

## Prompting

Use `system_prompt_text_maintenance.txt` as additional prompt. Typical user request:

> Prüfe die Texte von Programm ZMY_REPORT, korrigiere Rechtschreibung und Stil in DE und
> ergänze fehlende EN-Übersetzungen.

The assistant lists the texts, sends one `text_suggest` per text and language, then polls
`text_review_status` and answers retry / change / deny requests with `replaces_id`.
