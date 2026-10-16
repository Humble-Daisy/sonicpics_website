---
title: Identity System
description: Avatar and logo management with upload, crop, Gravatar, initials, and color customization
keywords: avatar logo identity picker crop upload gravatar initials color hue oklch image cropper active storage
---

# Identity System

ModelRails uses a unified identity picker for both user avatars and workspace logos. The same UI pattern — source selection, image cropping, and color customization — applies to both.

## Architecture

The identity picker is a two-view component:

1. **Hub** — server-rendered via Turbo Frame (`<turbo-frame id="identity-picker-hub">`), shows source cards and color picker
2. **Crop view** — client-side Cropper.js interface for adjusting uploaded images

### Stimulus Controllers

| Controller | Responsibility |
|-----------|---------------|
| `identity-picker` | Orchestrates hub/crop switching, file upload, save |
| `image-cropper` | Zoom, pan, keyboard navigation, crop coordinates |

## User Avatars

**Sources:** upload, gravatar, initials

| Source | How it works |
|--------|-------------|
| **Upload** | User selects an image, crops it, both cropped and original are stored |
| **Gravatar** | Fetched from gravatar.com based on email hash. Only shown if a Gravatar exists (checked async via `CheckGravatarJob`) |
| **Initials** | Two-letter initials from first and last name, rendered on a colored circle |

### Storage

Two Active Storage attachments per user:

- `avatar` — the cropped/display image (max 5 MB)
- `avatar_original` — the full upload for re-cropping (max 10 MB)

Crop coordinates are stored in the `avatar_original` blob's metadata so the crop can be restored when re-editing.

When switching away from the upload source, both attachments are purged to save storage.

### Accepted Formats

PNG, JPEG, GIF, WebP. GIF uploads show a warning that the crop result will be a static frame.

This allowlist is also what keeps avatars and logos clear of the libvips loaders Active Storage blocks as of Rails 8.1.3.1 — all four still transform normally. See [Security](security.md) for what changed and which formats no longer generate variants.

## Workspace Logos

**Sources:** upload, initials

Same pattern as user avatars but without Gravatar. Workspace logos use `logo` and `logo_original` attachments with the same size limits and format restrictions.

## Color System

Both users and workspaces have a `primary_color` field — an integer hue value from 0 to 360.

### How Colors Are Applied

Colors use the OKLCH color space with CSS custom properties for CSP safety:

```html
<div style="--hue: 210" class="bg-hue-initials">
  <!-- background-color: oklch(0.35 0.20 var(--hue)) -->
</div>
```

Two utility classes handle the two use cases:

| Class | OKLCH Values | Purpose |
|-------|-------------|---------|
| `.bg-hue-initials` | L=0.35, C=0.20 | Initials circle background (dark, high chroma) |

### Why OKLCH?

OKLCH provides perceptually uniform color — a hue slider from 0 to 360 produces colors that look equally vibrant and have consistent contrast with white text. This means any hue value meets AAA contrast for white text on the initials background.

## Image Cropping

The crop interface uses Cropper.js v2 with:

- **1:1 aspect ratio** enforced (square crop for circular avatars)
- **Zoom slider** with percentage display
- **Keyboard navigation** — arrow keys move the crop area, +/- keys zoom
- **Dimension badge** showing the crop output size in pixels
- **Live preview** — a circular preview updates as you adjust

### Accessibility

- Crop area has `role="application"` with keyboard handlers
- Zoom slider has proper ARIA attributes (valuemin, valuemax, valuenow)
- ARIA live regions announce crop readiness, reset, and zoom changes
- All interactive elements meet the 44px minimum touch target

## Re-Cropping

When a user re-opens the crop view for an existing upload, the original (uncropped) image is loaded — not the previously cropped version. This prevents progressive quality degradation from re-cropping a JPEG multiple times.

## Removing an Image

The delete action (`DELETE /account/avatar` or `DELETE /workspaces/:slug/logo`) purges both attachments and resets the source to "initials". This uses a standard `button_to` with `method: :delete` — no custom JavaScript fetch needed.

The picker takes the remove target as its own required local, `remove_url:`, separate from `form_url:`, which is where saves go. They are different resources: a workspace's logo saves through `workspaces#update`, so passing its `form_url` as the remove target would send **Remove photo** to `workspaces#destroy` and discard the whole workspace (#1402). A new caller names both.
