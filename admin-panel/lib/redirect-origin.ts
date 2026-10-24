export function applyRedirectOrigin(
  target: Pick<URL, "host" | "port" | "protocol">,
  host: string | null,
  protocol: string | null,
) {
  if (protocol === "http" || protocol === "https") {
    target.protocol = `${protocol}:`;
  }
  if (host) {
    target.host = host;
    target.port = new URL(`${target.protocol}//${host}`).port;
  }
}
