import { ServiceUnavailableException } from "@nestjs/common";
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "node:crypto";
/** AES-256-GCM with the server-only BOOKING_SECRETS_KEY (base64, 32 bytes). */
function secretKey() {
  const raw = process.env.BOOKING_SECRETS_KEY ?? "";
  const key = Buffer.from(raw, "base64");
  if (key.length !== 32)
    throw new ServiceUnavailableException(
      "Server secret storage is not configured. Set BOOKING_SECRETS_KEY.",
    );
  return key;
}
export function sealSecret(plain: string) {
  const iv = randomBytes(12),
    cipher = createCipheriv("aes-256-gcm", secretKey(), iv);
  const data = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
  return ["v1", iv, cipher.getAuthTag(), data]
    .map((p) => (typeof p === "string" ? p : p.toString("base64")))
    .join(".");
}
export function openSecret(sealed: string) {
  const [v, iv, tag, data] = sealed.split(".");
  if (v !== "v1") throw new Error("Unknown secret format");
  const decipher = createDecipheriv(
    "aes-256-gcm",
    secretKey(),
    Buffer.from(iv, "base64"),
  );
  decipher.setAuthTag(Buffer.from(tag, "base64"));
  return Buffer.concat([
    decipher.update(Buffer.from(data, "base64")),
    decipher.final(),
  ]).toString("utf8");
}
export const hashToolKey = (key: string) =>
  createHash("sha256").update(key).digest("hex");
