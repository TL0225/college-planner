# TestCatalogs regression corpus

Seed directory for catalog PDF regression fixtures used by `CatalogPDFRemediationTests` and `PDFCatalogIngestFixtureTests`.

## Layout
- Place representative PDF bulletins here as they are discovered in production.
- Name files `{school-key}.pdf` (e.g. `fordham.pdf`, `cmu.pdf`).
- Every production parsing bug should add a minimal fixture + a focused test.

## Current fixtures
Primary fixtures live in `CollegeTests/Fixtures/PDF/` (see `PDF_CATALOG_FIXTURES_DIR`).

This directory is reserved for additional regression samples as the scraper matures.
