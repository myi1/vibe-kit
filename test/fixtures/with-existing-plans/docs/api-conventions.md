# API conventions

Reference doc. Stable.

- All endpoints under `/api/v1`
- JSON request/response
- Standard error envelope: `{ "error": { "code": "...", "message": "..." } }`
- Auth: Bearer token in `Authorization` header
