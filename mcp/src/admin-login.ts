#!/usr/bin/env node
import {
  SarvamTokenStore,
  loginSarvam,
  ProviderLoginError,
} from "./admin/sarvam-auth.js";
import { loadAdminEnvironment } from "./admin/client.js";

async function main() {
  await loadAdminEnvironment();
  const command = process.argv[2] ?? "login";
  const tokenFile = process.env.BOOKINGOS_SARVAM_TOKEN_FILE;
  const store = new SarvamTokenStore(tokenFile);
  if (command === "status") {
    process.stdout.write(JSON.stringify(await store.status()) + "\n");
    return;
  }
  if (command === "logout") {
    await store.remove();
    process.stdout.write(
      "Removed this integration's local Sarvam authorization. Codex's separate Sarvam connection was not changed.\n",
    );
    return;
  }
  if (command !== "login")
    throw new ProviderLoginError(
      "Usage: node dist/admin-login.js [login|status|logout]",
    );
  const configuredPort = process.env.BOOKINGOS_SARVAM_CALLBACK_PORT;
  await loginSarvam({
    tokenFile,
    ...(configuredPort ? { port: Number(configuredPort) } : {}),
    clientId: process.env.SARVAM_OAUTH_CLIENT_ID,
    clientSecret: process.env.SARVAM_OAUTH_CLIENT_SECRET,
    issuer: process.env.SARVAM_OAUTH_ISSUER,
    onAuthorizationUrl(url) {
      process.stdout.write(
        "Open this official Sarvam sign-in link in your browser, approve the requested workspace, then return here:\n" +
          url.toString() +
          "\n",
      );
    },
  });
  process.stdout.write(
    "Sarvam authorization saved privately. Resume the existing BookingOS connection job.\n",
  );
}
main().catch((error) => {
  process.stderr.write(
    (error instanceof ProviderLoginError
      ? error.message
      : "Sarvam authorization could not complete safely.") + "\n",
  );
  process.exitCode = 1;
});
