// Screenshot saves: the Share Extension uploads up to SCREENSHOT_MAX_COUNT
// JPEGs to the private `screenshots` bucket at {user_id}/{batch_id}/{n}.jpg,
// then sends their paths to process-url. The paths come from the client, so
// only the caller's own folder and this exact shape are accepted: the function
// downloads with the service role, which would otherwise read anyone's files.

export const SCREENSHOT_BUCKET = 'screenshots';
export const SCREENSHOT_MAX_COUNT = 10;

const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const PATH = new RegExp(`^(${UUID})/(${UUID})/(\\d{1,2})\\.jpg$`);

/**
 * The paths in the order given (the order the screenshots were picked), or
 * null when any is malformed, outside the user's folder, from more than one
 * batch, repeated, or when there are none or too many.
 */
export function screenshotPaths(input: unknown, userId: string): string[] | null {
  if (!Array.isArray(input) || input.length === 0 || input.length > SCREENSHOT_MAX_COUNT) return null;

  const paths: string[] = [];
  let batch: string | null = null;
  for (const raw of input) {
    if (typeof raw !== 'string') return null;
    const path = raw.toLowerCase();
    const match = path.match(PATH);
    if (!match || match[1] !== userId.toLowerCase()) return null;
    if (batch !== null && match[2] !== batch) return null;
    batch = match[2];
    if (paths.includes(path)) return null;
    paths.push(path);
  }
  return paths;
}
