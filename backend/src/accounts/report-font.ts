import { resolve } from "node:path";
/** Edge deployment replaces this module with the same embedded licensed font. */
export function reportFont(): string {
  return resolve("assets/fonts/NotoSans-Regular.ttf");
}
