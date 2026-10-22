import { BadRequestException } from "@nestjs/common";
import { z } from "zod";

export const websiteImageSchema = z
  .object({
    version: z.number().int().positive(),
    kind: z.enum(["hero", "space"]),
    business_id: z.uuid().optional(),
    resource_id: z.string().min(1).max(100).optional(),
    content_type: z.enum(["image/jpeg", "image/png", "image/webp"]),
    base64: z
      .string()
      .min(1)
      .max(1398104)
      .regex(
        /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/,
      ),
  })
  .strict()
  .refine(
    (v) =>
      v.kind === "hero"
        ? !v.business_id && !v.resource_id
        : !!v.business_id && !!v.resource_id,
    "Choose the business and booking space for a space photo.",
  );

/** Bound both transfer size and decoded pixels. Only JPEG, PNG and WebP raster content is accepted. */
export function websiteImage(input: z.infer<typeof websiteImageSchema>) {
  const data = Buffer.from(input.base64, "base64");
  let width = 0,
    height = 0;
  if (data.length < 24 || data.length > 1024 * 1024)
    throw new BadRequestException("Choose an image up to 1 MB.");
  if (
    input.content_type === "image/png" &&
    data
      .subarray(0, 8)
      .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
    data.toString("ascii", 12, 16) === "IHDR"
  ) {
    width = data.readUInt32BE(16);
    height = data.readUInt32BE(20);
  } else if (
    input.content_type === "image/jpeg" &&
    data[0] === 255 &&
    data[1] === 216
  ) {
    let i = 2;
    while (i + 8 < data.length && data[i] === 255) {
      while (i < data.length && data[i] === 255) i++;
      if (i + 3 >= data.length) break;
      const marker = data[i++];
      if (marker === 0xd9 || marker === 0xda) break;
      if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      const length = data.readUInt16BE(i);
      if (length < 2 || i + length > data.length) break;
      if ([0xc0, 0xc1, 0xc2].includes(marker) && length >= 8) {
        height = data.readUInt16BE(i + 3);
        width = data.readUInt16BE(i + 5);
        break;
      }
      i += length;
    }
  } else if (
    input.content_type === "image/webp" &&
    data.toString("ascii", 0, 4) === "RIFF" &&
    data.toString("ascii", 8, 12) === "WEBP"
  ) {
    const format = data.toString("ascii", 12, 16);
    if (format === "VP8X" && data.length >= 30 && !(data[20] & 2)) {
      width = data.readUIntLE(24, 3) + 1;
      height = data.readUIntLE(27, 3) + 1;
    } else if (
      format === "VP8 " &&
      data.length >= 30 &&
      data.toString("hex", 23, 26) === "9d012a"
    ) {
      width = data.readUInt16LE(26) & 0x3fff;
      height = data.readUInt16LE(28) & 0x3fff;
    } else if (format === "VP8L" && data.length >= 25 && data[20] === 0x2f) {
      const bits = data.readUInt32LE(21);
      width = (bits & 0x3fff) + 1;
      height = ((bits >>> 14) & 0x3fff) + 1;
    }
  }
  if (
    !width ||
    !height ||
    width > 8192 ||
    height > 8192 ||
    width * height > 24000000
  )
    throw new BadRequestException(
      "Choose a valid JPEG, PNG or WebP photo up to 24 megapixels.",
    );
  return data;
}
