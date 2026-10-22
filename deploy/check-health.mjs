try {
  const response = await fetch(`http://127.0.0.1:${process.env.PORT || 8080}/_health`, {
    signal: AbortSignal.timeout(6000),
  });
  if (!response.ok) process.exitCode = 1;
} catch {
  process.exitCode = 1;
}
