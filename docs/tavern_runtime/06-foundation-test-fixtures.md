# Foundation fixture coverage

Synthetic fixtures in `test/data/sqlite/sqlite_tavern_foundation_test.dart` cover basic Session, five Alternatives on one Turn, nested Story Lines, rich Content Parts (text/reasoning/tool invocation/result), three failed/cancelled/completed retry Attempts, and a 1000-Turn/5000-Alternative long history. They contain no user data or Provider calls.

The same semantic exercise runs against SQLite and in-memory repositories. Additional checks cover inherited selection snapshots (including nested ancestors), branch-origin Alternative deletion protection, cross-session speaker rejection, reopen persistence, migration failure rollback, atomic Alternative/Attempt creation, archive fresh/merge semantic roundtrip, unknown Part preservation, tool-call linkage, and visible-vs-reasoning projection. The large fixture projects 1000, 500 and 100 inherited Turns and asserts a generous bounded query time; it is a regression guard, not a device benchmark.

Future slices must add real Provider and Prompt tests independently. SillyTavern chat import is not implemented, but stable Turn/Alternative/branch IDs, typed rich Parts and preserved Attempt history leave clear mapping points for alternatives, swipes, branches, tool metadata and reasoning. The Phase 5 blind-test comprehension question remains open despite this foundation's automated correctness tests.
