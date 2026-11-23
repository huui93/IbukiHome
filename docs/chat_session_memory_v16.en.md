# Local conversation memory

[简体中文](chat_session_memory_v16.md) · **English**

This guide describes IbukiHome Android v1.1.0 and SQLite schema v22. The file name records the SQLite v16 migration that introduced session-scoped memory.

Each chat conversation owns its context, saved memories, summaries, search results, and memory controls. Conversations with the same persona have independent data. Fiction manages its own runtime and data. The modes share model and API configuration.

## Search and local storage

Memory search ranks the current local records using Chinese single characters and bigrams, English words, limited query expansion, pinned entries, deduplication, and count and character budgets. Different wording and ambiguous references can reduce recall. The design draws on public descriptions of saved memory, history reference, editable overviews, source inspection, and forgetting. [Memory in ChatGPT](https://help.openai.com/en/articles/8590148-memory-in-chatgpt) · [ChatGPT memory dreaming](https://openai.com/index/chatgpt-memory-dreaming/)

| SQLite table | Purpose |
| --- | --- |
| `chat_memory_entries` | Session-scoped facts that can be edited, pinned, deleted, and restored. Entries include topics and source fingerprints. |
| `conversation_summaries` | Summaries with source ranges and fingerprints. Before using them, the app checks whether editing or deleting the source invalidated the summary or extracted facts. |
| `chat_memory_states` | Saved memory and history switches, automatic saving, pause state, overview, processing cursor, and exclusions. |
| `chat_memory_usage` | IDs and content fingerprints for the sources supplied with a reply. The source view shows what the model received as context and omits a source when its recorded version is no longer available. |

Search runs locally. Automated summaries and fact extraction send the relevant conversation material to the model configured for that session. The application reports when organization is unavailable or fails.

Original messages and saved memories are separate records. Pausing stops memory reference and organization while retaining the conversation and its recent ordinary context. **Clear and disable** moves saved memories to the deleted list and excludes existing history and summaries from memory use. **Stop referencing** filters matching sources from memory search and from the history included in the next model request. This includes recent messages. The transcript retains the original messages. A newly submitted message is treated as the current input.

## Context, compression, and saving

The prompt gives priority to the current message and the most recent 30 raw messages. With history reference enabled, the request can include unsummarized continuous history within the budget, the latest valid summary, older keyword matches, and saved facts. Supplementary context is limited to eight sources, 6,000 characters in total, and 1,400 characters per source. The model configuration can reduce the budget. Pinned entries and manual revisions take priority. The app uses saved context and output limits when available and conservative local estimates otherwise.

Only one organization job runs per conversation. Automatic compression defaults to **50 completed turns**. A turn is a user message followed by a successfully completed AI reply. Change the threshold or run compression immediately under **Settings → Chat memory → Conversation**. The app batches work by message count and text size. History reference controls summary storage. Automatic saving controls fact extraction. A pause or relevant setting change cancels the current job and prevents additional organization requests from that job.

Automatic extraction is instructed to retain facts explicitly stated or confirmed by the user and to require a clear request before remembering sensitive information. It can update automatically saved facts on the same topic. Pinned and manually edited entries are protected. Review the original sources and edit incorrect inferences in memory management.

With automatic saving enabled and memory active, successful image recognition immediately stores a source-linked observation in that conversation. It reuses the recognition output and does not need a separate inference request. The observation is labeled as model-generated and may be inaccurate. The description remains searchable on the original image record when automatic saving is disabled.

An explicit `记住：…` or `remember …` instruction can save a fact immediately. An explicit `忘记…` or `forget …` instruction can stop reference to the specified saved entry. The management screen handles ambiguous requests. Regenerating a previously answered message does not replay its memory commands. Organization respects exclusions when selecting source material.

## Concurrency, migration, and backup

Before a model call, the job reads the session memory state's revision. On return it validates the source prefix and commits against the expected revision in a transaction. If the summary succeeds and fact extraction fails, it retains the summary and keeps the cursor in place so that a retry can reuse it. Changes to settings, manual edits, and forgetting advance the revision. SQLite transactions stay outside network requests.

The original SQLite v15 to v16 migration copied persona-level switches into newly initialized sessions. Each session then manages its own settings. Legacy facts with no verified session remain read-only. Dart validates the JSON fields so this storage does not require SQLite JSON functions.

Backups include conversation memory settings and reply source records. Merge rewrites session, message, fact, summary, and internal JSON references. It recomputes a source fingerprint only if the original source matched. Invalid JSON or cross-session associations cause restore to roll back. [Backup format](backup/IBUKI_BACKUP_FORMAT_V1.md)

## Verification

The v1.1.0 release passed 1,893 offline tests, with 19 skips. Memory coverage includes conversation isolation, budgets, source invalidation, concurrent edits and pauses, reopening the database, and backup restore. Summary quality and recall with a live provider depend on the configured model. [v1.1.0 release evidence](https://github.com/huui93/IbukiHome/releases/tag/v1.1.0)
