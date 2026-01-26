# UB Export Audit Resolution

Input: University_at_Buffalo_scraped_catalog_1767942552.csv

## Fixes Applied

- Filled missing course titles: 4
- Filled missing course credits: 6074
- Filled missing course descriptions: 5550
- Replaced generic department labels via directory mapping: 6352

## Network Repairs (Course Previews)

- Unique course codes needing network repair (post intra-export fill): 150
- Course codes found via listing pages: 67
- Rows filled (title): 0
- Rows filled (credits): 233
- Rows filled (description): 0

## AUDIT Fixups (Missing Credits)

- Unresolved AUDIT rows targeted: 4635
- Unique course codes targeted: 4622
- Unique codes found via listing pages: 4621
- AUDIT rows credits filled: 4588
- AUDIT rows unresolvable (no preview URL found): 14
- AUDIT rows unresolvable (preview has no credits marker): 33

## Remaining Gaps (CATALOG rows)

- missing_credits: 99
- missing_title: 1
- missing_description: 299
- generic_department: 0

## AUDIT Rows Summary

- Total AUDIT rows: 10423
- Course-related AUDIT rows marked RESOLVED: 5596
- By entity:
  - CourseCatalogEntity: 9517
  - DegreeRequirementEntity.requiredCoursesDetailedJSON: 718
  - DegreeRequirementEntity.selectFromDetailedJSON: 97
  - MajorEntity: 90
  - CatalogScrapeStateEntity: 1

- Top issues:
  - RESOLVED: Partial course row: missing credits: 9469
  - RESOLVED: Partial course detail: missing credits: 713
  - Partial course detail: missing credits: 99
  - Program saved to database but no requirements found: 89
  - UNRESOLVABLE: Partial course row: missing credits (preview page has no credits marker): 33
  - UNRESOLVABLE: Partial course row: missing credits (no preview URL found): 14
  - RESOLVED: Partial course detail: missing title, credits: 2
  - AUDIT SUMMARY: catalog courses: 9583; described rows: 9583/9583; unique described codes: 9583: 1
  - AUDIT SUMMARY: programs: 720 (with requirements: 631, without: 89); by degreeLevel: [Doctorate / Professional=89; Graduate (Masters)=268; Undergraduate=363]; by catoid: [17=363; 19=342; 22=8; 23=6; 24=1]: 1
  - AUDIT SUMMARY: course scrape states by catoid: [17=3967; 19=4873; 22=470; 23=100; 24=174]: 1
  - Partial course detail: missing title: 1

## Probe: Programs flagged as missing requirements

This does NOT re-scrape requirements into structured rows; it only checks whether
the program pages appear to contain requirement markers or course list HTML.

- Programs probed: 89
- Pages with requirement markers: 70
- Pages with acalog course list items: 79
- Total unique course-code hits (sum across pages): 445

Examples (first 10):
- Adult-Gerontology Clinical Nurse Specialist (Post-MS) DNP, MS: https://catalogs.buffalo.edu/preview_program.php?poid=7734&catoid=19
- Adult/Gerontology Nurse Practitioner (Post-MS) DNP: https://catalogs.buffalo.edu/preview_program.php?poid=7362&catoid=19
- Adult/Gerontology Nurse Practitioner DNP: https://catalogs.buffalo.edu/preview_program.php?poid=7363&catoid=19
- Affordable Housing Advanced Certificate: https://catalogs.buffalo.edu/preview_program.php?poid=7364&catoid=19
- Applied Economics - Financial Specialization Advanced Certificate: https://catalogs.buffalo.edu/preview_program.php?poid=7722&catoid=19
- Assistive and Rehabilitative Technology (CART) Advanced Certificate: https://catalogs.buffalo.edu/preview_program.php?poid=8426&catoid=19
- Bilingual Education Advanced Certificate: https://catalogs.buffalo.edu/preview_program.php?poid=7399&catoid=19
- Biomedical Informatics, PHD: https://catalogs.buffalo.edu/preview_program.php?poid=7396&catoid=19
- Biostatistical Informatics Advanced Certificate: https://catalogs.buffalo.edu/preview_program.php?poid=7403&catoid=19
- Business Practices in the U.S. Micro-Credential: https://catalogs.buffalo.edu/preview_program.php?poid=7697&catoid=19

