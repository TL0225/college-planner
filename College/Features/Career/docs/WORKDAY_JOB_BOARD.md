# Workday Job Board — In-app scraper

College scrapes public Workday career boards over HTTPS using the user’s network connection (no proxy). Listings are stored in local store and shown under **Career → Openings**.

## Settings

**Settings → Workday**

- Add companies with a `*.myworkdayjobs.com` careers board URL
- Automatic refresh: Manual / 1h / 3h / 6h / **12h (default)** / 24h
- Background refresh uses `NSBackgroundActivityScheduler` (best-effort; macOS may defer runs)

## API endpoints (derived from careers URL)

Given: `https://TENANT.wd5.myworkdayjobs.com/en-US/BOARD`

| Operation | Method | URL |
|-----------|--------|-----|
| List jobs | POST | `https://HOST/wday/cxs/TENANT/BOARD/jobs` |
| Job detail | GET | `https://HOST/wday/cxs/TENANT/BOARD` + `externalPath` |

`externalPath` from the list response starts with `/job/`, e.g. `/job/NJ-Corporate-Headquarters/Manager--Quality-Control_R3470`.

List body:

```json
{"appliedFacets": {}, "limit": 20, "offset": 0, "searchText": ""}
```

## Scrape behavior

1. **List scrape** (manual, scheduled, or on launch): paginated POST; 1–2s delay between pages; serial queue across companies.
2. **Detail scrape** (on demand when opening a job): GET detail URL; cached **48 hours** unless user taps “Refresh details”.
3. **Dedup**: `(companySlug, externalPath)`; `listingHash` detects title/location edits and invalidates cached detail.
4. **Inactive jobs**: removed from list API for a company are marked `isActive = false` after a successful list scrape.
5. **Sort / filter**: `postedAt` is parsed from list `postedOn` (e.g. “Posted 6 Days Ago”). Aggregate list locations like “19 Locations” are replaced with the slug from `externalPath`; opening a job loads detail `location` + `additionalLocations` for the location filter.

## Errors

| Error | Meaning |
|-------|---------|
| `badURL` | Careers URL could not be parsed |
| `requiresAuth` | 401 or redirect to a different host (internal board) |
| `rateLimited` | Too many 429 responses |
| `decodingFailed` | Unexpected JSON shape |

## Privacy

Outbound HTTPS to user-entered URLs only. Requires standard network client entitlement.
