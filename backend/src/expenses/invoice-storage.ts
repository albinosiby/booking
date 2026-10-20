import { BadRequestException } from "@nestjs/common";
export const invoiceBucket = "expense-invoices";
export const invoiceTypes = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
] as const;
export interface InvoiceStorage {
  upload(path: string): Promise<string>;
  verify(path: string, type: string, size: number): Promise<void>;
  download(path: string): Promise<string>;
  remove(paths: string[]): Promise<void>;
}
export class InvoiceValidationError extends BadRequestException {}
export class SupabaseInvoiceStorage implements InvoiceStorage {
  private async request(path: string, init: RequestInit = {}) {
    const url = process.env.SUPABASE_URL,
      key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!url || !key)
      throw new BadRequestException("Invoice storage is not configured.");
    const response = await fetch(`${url}/storage/v1/${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${key}`,
        apikey: key,
        "Content-Type": "application/json",
        ...init.headers,
      },
      signal: AbortSignal.timeout(20000),
    });
    if (!response.ok)
      throw new BadRequestException(
        "Invoice storage could not complete the request. Please retry.",
      );
    return response;
  }
  private object(path: string) {
    return `${invoiceBucket}/${path.split("/").map(encodeURIComponent).join("/")}`;
  }
  async upload(path: string) {
    const data = await (
      await this.request(`object/upload/sign/${this.object(path)}`, {
        method: "POST",
        body: "{}",
      })
    ).json();
    return `${process.env.SUPABASE_URL}/storage/v1${data.url}`;
  }
  async verify(path: string, type: string, size: number) {
    const info = await (
      await this.request(`object/info/${this.object(path)}`)
    ).json();
    if (
      Number(info.size ?? info.metadata?.size) !== size ||
      (info.content_type ?? info.contentType ?? info.metadata?.mimetype) !==
        type
    )
      throw new InvoiceValidationError(
        "Uploaded invoice type or size does not match.",
      );
    const response = await this.request(`object/${this.object(path)}`, {
      headers: { Range: "bytes=0-1023" },
    });
    const reader = response.body!.getReader();
    const prefix = new Uint8Array(1024);
    let length = 0;
    try {
      while (length < prefix.length) {
        const { done, value } = await reader.read();
        if (done) break;
        const chunk = value.subarray(0, prefix.length - length);
        prefix.set(chunk, length);
        length += chunk.length;
      }
    } finally {
      await reader.cancel();
    }
    if (!validInvoice(prefix.subarray(0, length), type))
      throw new InvoiceValidationError(
        "Choose a valid JPEG, PNG, WebP image or PDF.",
      );
  }
  async download(path: string) {
    const data = await (
      await this.request(`object/sign/${this.object(path)}`, {
        method: "POST",
        body: JSON.stringify({ expiresIn: 300 }),
      })
    ).json();
    return `${process.env.SUPABASE_URL}/storage/v1${data.signedURL}`;
  }
  async remove(paths: string[]) {
    if (paths.length)
      await this.request(`object/${invoiceBucket}`, {
        method: "DELETE",
        body: JSON.stringify({ prefixes: paths }),
      });
  }
}
export function validInvoice(data: Uint8Array, type: string) {
  const ascii = (start: number, end: number) =>
    new TextDecoder().decode(data.subarray(start, end));
  if (type === "application/pdf") return ascii(0, 1024).includes("%PDF-");
  if (type === "image/jpeg")
    return data[0] === 255 && data[1] === 216 && data[2] === 255;
  if (type === "image/png")
    return [137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => data[i] === v);
  return (
    type === "image/webp" && ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP"
  );
}
