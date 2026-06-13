# Test fixtures — attribution

These PNG fixtures are vendored from **mapbox/pixelmatch** v5.3.0
(https://github.com/mapbox/pixelmatch/tree/v5.3.0/test/fixtures), used to
validate AppLens's first-party Dart port of the pixelmatch algorithm
(`lib/src/pixelmatch.dart`) byte-for-byte against the upstream reference.

pixelmatch is licensed **ISC, © 2019 Mapbox**:

```
Permission to use, copy, modify, and/or distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.
```

Expected mismatch counts (from the upstream v5.3.0 test suite):
`1a↔1b = 143` (threshold 0.05), `3a↔3b = 212` (0.05), `6a↔6b = 51` (0.05),
`7a↔7b = 2448` (default threshold 0.1, diffColorAlt).
