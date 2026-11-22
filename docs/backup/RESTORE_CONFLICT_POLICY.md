# Restore Conflict Policy

V1 supports fresh restore and non-destructive merge. It deliberately does not expose a replace-all mode.

Fresh restore requires an empty user-content store. Merge does not infer identity from names: same-name characters, projects, worlds, or books may be distinct. If an Archive ID already exists locally, the restore map creates a new Local ID and rewrites all foreign keys and supported ID arrays consistently. Existing rows are never silently overwritten.

The complete archive is extracted to a private staging directory and validated before restore. Assets are copied to an operation-owned private directory; database rows are inserted in one exclusive transaction. A database failure rolls back every inserted row and removes promoted operation assets. A partial asset copy removes its operation directory before any database write.

Cyclic current pointers (`defaultSession`, current scene/player/branch, and parent branch) are inserted as null and updated only after their targets exist. Compatibility payload links and logical ID arrays are remapped through the same restore map.
