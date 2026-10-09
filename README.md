# Katiba Yetu Web

A digital constitutional platform for Tanzania to read, explore, discuss, propose, and participate in constitutional matters.

## Constitutional source files

The application uses the original constitutional source files directly from:

- `public/katiba/Katiba/Tanzania/`
- `public/katiba/Katiba/Zanzibar/`
- `public/katiba/Rasimu za Katiba/Tanzania/`

These files are the source of truth. They are not merged, rewritten, normalized, or replaced by generated constitutional JSON.

Chapter files list the article files that belong to each chapter. The web service loads each chapter and then fetches the referenced original article JSON file.

Any future search index or cache must be treated as disposable infrastructure only; the original files remain authoritative.


<!-- Deployment trigger: 2026-10-01 admin console build fixes -->

<!-- Deployment retry: poll state scope fix -->
