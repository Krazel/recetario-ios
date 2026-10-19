export function requireAltoolSuccess(result, operation) {
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  const marker = operation === 'upload' ? 'UPLOAD SUCCEEDED' : 'VERIFY SUCCEEDED';
  if (result.error || result.status !== 0 || /(?:UPLOAD|VERIFY) FAILED|Failed to upload package/i.test(output) || !output.includes(marker)) {
    throw new Error(`altool ${operation} did not confirm success (exit ${result.status})`);
  }
  return output.match(/Delivery UUID:\s*([0-9a-f-]{36})/i)?.[1];
}
