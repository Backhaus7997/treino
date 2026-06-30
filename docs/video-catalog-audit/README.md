# Video Catalog Audit

- Drive folders scanned: 20
- Drive videos found: 7569
- Catalog exercises considered: 448
- Recommended exercise video matches: 113
- High confidence recommendations: 61
- Medium confidence recommendations: 0
- Low confidence recommendations: 52
- Unmatched videos: 6215
- Duplicate catalog families: 54
- Duplicate families that look like valid equipment variants: 26
- Duplicate families needing same-equipment review: 18
- Duplicate families needing generic/equipment review: 10

## Outputs

- `drive-videos.json`: raw Drive inventory.
- `video-match-details.json`: one best match per video.
- `video-recommendations.csv`: one recommended video per exercise.
- `video-recommendations-high-confidence.csv`: safe first batch candidates.
- `video-recommendations-review-needed.csv`: candidates that need human review.
- `catalog-duplicate-families.csv`: possible duplicate families.
- `catalog-duplicate-equipment-review.csv`: duplicate families classified by equipment.
- `unmatched-videos.csv`: videos with no catalog match.

## Notes

- This audit is report-only.
- Use only high-confidence rows automatically.
- Medium/low-confidence rows need human review before backfill.
- Drive URLs should not be used directly in the app. Upload approved files to Firebase Storage and persist those download URLs in `videoUrl`.

