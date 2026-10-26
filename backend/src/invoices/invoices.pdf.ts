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
export const INVOICE_TEMPLATES = [
  {
    id: "classic",
    name: "Classic",
    description: "Green accents with a simple ruled layout.",
  },
  {
    id: "modern",
    name: "Modern",
    description: "Bold coloured header band with the balance due highlighted.",
  },
  {
    id: "minimal",
    name: "Minimal",
    description: "Plain black and white, light on decoration.",
  },
] as const;
export type InvoiceTemplate = (typeof INVOICE_TEMPLATES)[number]["id"];
const THEMES: Record<
  InvoiceTemplate,
  {
    accent: string;
    band: boolean;
    rules: boolean;
    upper: boolean;
    tint: string;
  }
> = {
  classic: {
    accent: "#337418",
    band: false,
    rules: true,
    upper: false,
    tint: "",
  },
  modern: {
    accent: "#1F4E8C",
    band: true,
    rules: false,
    upper: false,
    tint: "#E8F0FA",
  },
  minimal: {
    accent: "#202020",
    band: false,
    rules: false,
    upper: true,
    tint: "",
  },
};
export async function renderInvoice(
  inv: Row,
  logo: InvoiceImage,
  qr: InvoiceImage,
): Promise<Buffer> {
  const s = inv.snapshot,
    cur: string = s.currency,
    theme =
      THEMES[
        (s.template as InvoiceTemplate) in THEMES
          ? (s.template as InvoiceTemplate)
          : "classic"
      ];
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
      green = theme.accent,
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
    const row = (
      k: string,
      v: string,
      bold = false,
      color = ink,
      highlight = false,
    ) => {
      if (highlight) doc.y += 6;
      const y = doc.y;
      if (highlight && theme.tint)
        doc.rect(L - 6, y - 4, W + 12, 22).fill(theme.tint);
      doc
        .font("Report")
        .fontSize(bold ? 11 : 10)
        .fillColor(color);
      doc.text(k, L, y, { width: 330 });
      doc.text(v, L + 330, y, { width: W - 330, align: "right" });
      doc.x = L;
      doc.y = Math.max(doc.y, y + (bold ? 15 : 13));
    };
    const section = (t: string) => {
      if (doc.y > 700) doc.addPage();
      doc.x = L;
      doc.moveDown(0.8);
      text(theme.upper ? t.toUpperCase() : t, theme.upper ? 9 : 12, green, {
        width: W,
        characterSpacing: theme.upper ? 1 : 0,
      });
      if (theme.rules)
        doc
          .moveTo(L, doc.y + 2)
          .lineTo(L + W, doc.y + 2)
          .strokeColor("#d0d0d0")
          .lineWidth(0.5)
          .stroke();
      doc.moveDown(0.5);
    };
    // Header: logo + organization on the left, invoice identity on the right.
    if (theme.band) doc.rect(0, 0, 595.28, 118).fill(green);
    const top = theme.band ? 28 : doc.y,
      headInk = theme.band ? "#FFFFFF" : ink,
      headSoft = theme.band ? "#DCE6F4" : grey;
    const hasLogo = image(logo, L, top, 56);
    const textX = hasLogo ? L + 68 : L;
    doc.x = textX;
    doc.y = top;
    text(s.organization.name, 16, headInk, { width: 300 });
    for (const line of s.organization.address_lines)
      text(line, 9, headSoft, { width: 300 });
    text(`Phone: ${s.organization.phone}`, 9, headSoft, { width: 300 });
    const leftEnd = doc.y;
    doc.x = L + 330;
    doc.y = top;
    text("INVOICE", theme.upper ? 14 : 20, theme.band ? "#FFFFFF" : green, {
      width: 177,
      align: "right",
      characterSpacing: theme.upper ? 3 : 0,
    });
    doc.x = L + 330;
    text(inv.invoice_number, 10, headInk, { width: 177, align: "right" });
    doc.x = L + 330;
    text(`Date: ${localLabel(s.generated_local)}`, 9, headSoft, {
      width: 177,
      align: "right",
    });
    doc.x = L;
    doc.y = Math.max(leftEnd, doc.y, top + 60) + (theme.band ? 30 : 6);
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
      true,
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
// Sample data for template previews; nothing is stored.
export function sampleInvoice(template: InvoiceTemplate, org: Row) {
  const currency = org.currency ?? "INR";
  return {
    invoice_number: "INV-000123",
    snapshot: {
      template,
      currency,
      generated_local: "2030-06-05T10:30",
      organization: {
        name: org.name,
        phone: org.phone,
        address_lines: org.address_lines,
      },
      customer: { name: "Asha Nair", phone: "9876500011" },
      booking: {
        reference: "BK-SAMPLE000123",
        status: "confirmed",
        business_name: "Badminton",
        space_name: "Court 1",
        option_name: "1 hour",
        people: 4,
        notes: "",
        local_start: "2030-06-07T18:00",
        local_end: "2030-06-07T19:00",
        timezone: "Asia/Kolkata",
      },
      price: {
        subtotal_minor: 70000,
        discount_minor: 5000,
        discount_reason: "Regular customer",
        total_minor: 65000,
      },
      payments: [
        {
          kind: "collection",
          method: "upi",
          amount_minor: 20000,
          local_received: "2030-06-05T10:15",
        },
      ],
      paid_minor: 20000,
      balance_minor: 45000,
      refund_due_minor: 0,
      bank_accounts: [
        {
          name: "Primary account",
          bank_name: "Sample Bank",
          last_four: "1234",
          account_number: "001234561234",
        },
      ],
      upi_id: "venue@bank",
    },
  };
}
