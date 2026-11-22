# Roundtrip Validation

Automated validation creates a v12 database containing a novel segment and revision, shared character image, Chat session and ordered messages, World prompt metadata, player and character instances, scene cast, current branch, feed, turn, lore, all four WorldBook reference types, and an inert compatibility payload.

The test exports an Archive v1 file, restores it into a newly created database and private asset directory, and verifies:

- content and revision rows survive;
- current World scene, branch, player, cast, feed, and turn survive;
- World, session, character, and persona book references survive;
- private images no longer depend on the source absolute path;
- Provider bindings restore as unconfigured;
- unknown/script compatibility text survives as inert data;
- credential fields and authorization values do not survive;
- merge creates a second entity on ID collision instead of replacing local content.

Archive tests also cover chunking, SHA-256 validation, corrupt checksum rejection, path traversal rejection, future-version rejection, and secret sanitization. All validation occurs without network, Provider, WebView, plugin runtime, or SecureStorage access.
