import { reportFont } from "../accounts/report-font";
type Row = Record<string, any>;
export type InvoiceImage = { data: Buffer; content_type: string } | null;
const label = (s: string) => (s === "upi" ? "UPI" : s.replaceAll("_", " "));
const money = (n: number, c: string) =>
  `${c === "INR" ? "₹" : c + " "}${(Number(n) / 100).toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];
// "2030-06-05T09:00" (venue local time) -> "05 Jun 2030, 09:00"
export const localLabel = (stamp: string) =>
  `${stamp.slice(8, 10)} ${MONTHS[Number(stamp.slice(5, 7)) - 1]} ${stamp.slice(0, 4)}, ${stamp.slice(11, 16)}`;
export async function renderInvoice(
  inv: Row,
  logo: InvoiceImage,
  qr: InvoiceImage,
): Promise<Buffer> {
  const s = inv.snapshot,
    cur: string = s.currency;
  const { default: PDFDocument } = await import("pdfkit");
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
        size: "A4",
        font: reportFont(),
        margin: 44,
        bufferPages: true,
        info: {
          Title: `Invoice ${inv.invoice_number}`,
          Author: s.organization.name,
        },
      }),
      chunks: Buffer[] = [];
    doc.on("data", (c) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);
    doc.registerFont("Report", reportFont());
    doc.font("Report");
    const L = 44,
      W = 507,
      ink = "#202020",
      green = "#337418",
      grey = "#666666";
    const image = (img: InvoiceImage, x: number, y: number, size: number) => {
      if (!img) return false;
      try {
        doc.image(img.data, x, y, { fit: [size, size] });
        return true;
      } catch {
        return false; // unsupported format (e.g. WebP) is left out rather than failing the invoice
      }
    };
    const text = (
      t: string,
      size = 10,
      color = ink,
      opts: Record<string, any> = {},
    ) => doc.font("Report").fontSize(size).fillColor(color).text(t, opts);
    const row = (k: string, v: string, bold = false, color = ink) => {
      const y = doc.y;
      doc
        .font("Report")
        .fontSize(bold ? 11 : 10)
        .fillColor(color);
      doc.text(k, L, y, { width: 330 });
      doc.text(v, L + 330, y, { width: W - 330, align: "right" });
      doc.y = Math.max(doc.y, y + (bold ? 15 : 13));
    };
    const section = (t: string) => {
      if (doc.y > 700) doc.addPage();
      doc.moveDown(0.8);
      text(t, 12, green, { width: W });
      doc
        .moveTo(L, doc.y + 2)
        .lineTo(L + W, doc.y + 2)
        .strokeColor("#d0d0d0")
        .lineWidth(0.5)
        .stroke();
      doc.moveDown(0.5);
    };
    // Header: logo + organization on the left, invoice identity on the right.
    const top = doc.y;
    const hasLogo = image(logo, L, top, 56);
    const textX = hasLogo ? L + 68 : L;
    doc.x = textX;
    doc.y = top;
    text(s.organization.name, 16, ink, { width: 300 });
    for (const line of s.organization.address_lines)
      text(line, 9, grey, { width: 300 });
    text(`Phone: ${s.organization.phone}`, 9, grey, { width: 300 });
    const leftEnd = doc.y;
    doc.x = L + 330;
    doc.y = top;
    text("INVOICE", 20, green, { width: 177, align: "right" });
    doc.x = L + 330;
    text(inv.invoice_number, 10, ink, { width: 177, align: "right" });
    doc.x = L + 330;
    text(`Date: ${localLabel(s.generated_local)}`, 9, grey, {
      width: 177,
      align: "right",
    });
    doc.x = L;
    doc.y = Math.max(leftEnd, doc.y, top + 60) + 6;
    section("Billed to");
    text(s.customer.name, 11, ink, { width: W });
    text(`Phone: ${s.customer.phone}`, 10, ink, { width: W });
    section("Booking");
    row("Reference", s.booking.reference);
    row(
      "Business / space",
      `${s.booking.business_name} / ${s.booking.space_name}`,
    );
    if (s.booking.option_name) row("Option", s.booking.option_name);
    row(
      "Date and time",
      `${localLabel(s.booking.local_start)} – ${s.booking.local_end.slice(11, 16)}`,
    );
    row("People", String(s.booking.people));
    row("Status", label(s.booking.status));
    if (s.booking.notes) row("Notes", s.booking.notes);
    section("Charges");
    row("Subtotal", money(s.price.subtotal_minor, cur));
    if (s.price.discount_minor)
      row(
        `Discount${s.price.discount_reason ? ` (${s.price.discount_reason})` : ""}`,
        `- ${money(s.price.discount_minor, cur)}`,
      );
    row("Total", money(s.price.total_minor, cur), true);
    if (s.payments.length) {
      doc.moveDown(0.4);
      text("Payments received", 10, grey, { width: W });
      for (const p of s.payments)
        row(
          `${p.kind === "refund" ? "Refund" : "Paid"} – ${label(p.method)} – ${localLabel(p.local_received)}`,
          `${p.kind === "refund" ? "- " : ""}${money(p.amount_minor, cur)}`,
        );
    }
    doc.moveDown(0.4);
    row("Amount paid so far", money(s.paid_minor, cur), true);
    row(
      "Amount to pay (balance due)",
      money(s.balance_minor, cur),
      true,
      green,
    );
    if (s.refund_due_minor)
      row("Refund due to customer", money(s.refund_due_minor, cur));
    const hasBank = s.bank_accounts.length > 0,
      hasUpi = !!s.upi_id || !!qr;
    if (s.balance_minor > 0 && (hasBank || hasUpi)) {
      if (doc.y > 560) doc.addPage();
      section("How to pay");
      for (const a of s.bank_accounts) {
        text(a.name, 10, ink, { width: W });
        if (a.bank_name) text(`Bank: ${a.bank_name}`, 10, ink, { width: W });
        text(
          a.account_number
            ? `Account number: ${a.account_number}`
            : `Account ending: ${a.last_four}`,
          10,
          ink,
          { width: W },
        );
        doc.moveDown(0.4);
      }
      if (s.upi_id) text(`UPI ID: ${s.upi_id}`, 11, ink, { width: W });
      if (qr) {
        doc.moveDown(0.4);
        const y = doc.y;
        if (image(qr, L, y, 130)) doc.y = y + 136;
      }
    }
    const range = doc.bufferedPageRange();
    for (let i = 0; i < range.count; i++) {
      doc.switchToPage(i);
      doc
        .fontSize(8)
        .fillColor(grey)
        .text(
          `${inv.invoice_number} | ${s.organization.name} | Page ${i + 1} of ${range.count}`,
          L,
          805,
          { lineBreak: false },
        );
    }
    doc.end();
  });
}
