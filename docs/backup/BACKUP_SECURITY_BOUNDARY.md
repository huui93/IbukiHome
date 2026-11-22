# Backup Security Boundary

Full Archive & Restore is an offline content feature. It performs no HTTP request, Provider request, script execution, WebView injection, or SecureStorage write.

The snapshot source is an explicit content-table whitelist. It never reads SecureStorage, Provider credential configuration, installed plugin packages, plugin private storage, cookies, OAuth state, or authorization headers. Provider IDs and models attached to projects or sessions are removed from archive rows.

Compatibility payloads remain inert data so future adapters can remap preserved SillyTavern fields. Before serialization, credential-shaped keys are removed recursively and bearer/key-shaped values are redacted. JavaScript, Tavern Helper, RUBY concepts, and remote URLs may remain as text; restore only inserts sanitized data and never dispatches it to a runtime or network client.

Only existing content assets below IbukiHome's private application-support directory may be copied. External absolute paths are not archived. Data rows contain `ibuki-asset://<digest>` references, which are replaced with new private paths during restore.

Any active Novel, Chat, World, Auto Story, or Plugin AI operation blocks snapshot creation. This prevents a half-completed generation from becoming a backup boundary.
