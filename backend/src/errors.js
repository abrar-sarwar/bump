// A single error type for everything that should reach the client as
// `{ "error": { "code", "message" } }` (see CONTRACT.md → Errors).
// Messages are written to be safe to show to the user: they never contain
// user text, upstream bodies, or secrets.

export class ApiError extends Error {
  constructor(status, code, message, headers = {}) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.headers = headers;
  }
}

export const badRequest = (message) => new ApiError(400, 'bad_request', message);
export const tooLarge = () => new ApiError(413, 'too_large', 'Request body is too large.');
export const upstreamInvalid = () =>
  new ApiError(502, 'upstream_invalid', 'The AI service returned an unusable answer.');
export const upstreamError = () =>
  new ApiError(502, 'upstream_error', 'The AI service returned an error.');
export const upstreamTimeout = () =>
  new ApiError(504, 'upstream_timeout', 'The AI service did not answer in time.');
export const notConfigured = () =>
  new ApiError(503, 'not_configured', 'The AI service is not configured on this server.');
export const storageNotConfigured = () =>
  new ApiError(503, 'storage_not_configured', 'Saving is not configured on this server.');
export const storageError = () =>
  new ApiError(502, 'storage_error', 'The transcript could not be saved.');
