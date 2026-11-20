#ifndef UT3_APPLE_PRODUCT_KEY_H
#define UT3_APPLE_PRODUCT_KEY_H

/* Optional owner-supplied file, loaded before starting the engine thread.
 * Returns 1 when loaded, 0 if absent, -1 for an unreadable/malformed file.
 * documents may be NULL (macOS); iOS checks its shared Documents folder first.
 * Neither key contents nor a key-derived fingerprint are logged. */
int ut3_apple_configure_product_key(const char *game, const char *data, const char *documents);
int ut3_apple_install_product_key(void);
int ut3_apple_has_product_key_file(void);

#endif
