import { reportFont } from "./report-font";
type Row = Record<string, any>;
const label = (s: string) => (s === "upi" ? "UPI" : s.replaceAll("_", " "));
const money = (n: number, c: string) =>
  `${c === "INR" ? "₹" : c} ${(Number(n) / 100).toFixed(2)}`;
export async function renderReport(
  d: Row,
  format: string,
  type: string,
): Promise<Buffer> {
  const s = d.selected;
  const summary = [
    ["Organization", d.name],
    ["Report", label(type)],
    ["From", d.from],
    ["Until", d.until],
    ["Timezone", d.timezone],
    [
      "Business filter",
      d.scope_business ?? "All businesses (including shared entries)",
    ],
    ["Space filter", d.scope_space ?? "All spaces"],
    ["Booking collections", s.collections_minor / 100],
    ["Extra income", s.extra_income_minor / 100],
    ["Total income", s.income_minor / 100],
    ["Refunds", s.refunds_minor / 100],
    ["Expenses", s.expenses_minor / 100],
    ["Net cash flow", s.net_minor / 100],
    ["Booking dues at cutoff", d.outstanding_minor / 100],
    ...Object.entries(s.income_methods ?? s.methods).map(([k, v]) => [
      `Total income - ${label(k)}`,
      Number(v) / 100,
    ]),
    ...Object.entries(s.methods).map(([k, v]) => [
      `Booking collections - ${label(k)}`,
      Number(v) / 100,
    ]),
  ];
  const bookingRows = d.bookings.map((b: Row) => {
    const net = b.payments.reduce(
      (n: number, p: Row) =>
        n + (p.kind === "collection" ? 1 : -1) * Number(p.amount_minor),
      0,
    );
    const methods = ["cash", "upi", "card", "bank_transfer"].map(
      (m) =>
        b.payments
          .filter((p: Row) => p.method === m)
          .reduce(
            (n: number, p: Row) =>
              n + (p.kind === "collection" ? 1 : -1) * p.amount_minor,
            0,
          ) / 100,
    );
    return [
      b.reference,
      b.customer,
      b.business,
      b.space,
      new Date(b.starts_at).toISOString(),
      b.status,
      (b.price_snapshot?.subtotal_minor ?? b.total_minor) / 100,
      (b.price_snapshot?.discount_minor ?? 0) / 100,
      b.total_minor / 100,
      net / 100,
      ...methods,
      b.received_to_date_minor / 100,
      Math.max(
        0,
        (b.status === "cancelled" ? 0 : b.total_minor) -
          b.received_to_date_minor,
      ) / 100,
    ];
  });
  const txRows = d.transactions.flatMap((e: Row) =>
    e.lines.map((l: Row) => [
      e.id,
      e.local_time,
      label(e.kind),
      e.booking_reference ?? "",
      e.business_name ?? "Shared / organization",
      e.space_name ?? "",
      e.category,
      e.reason,
      l.account_name,
      label(l.method),
      Number(l.amount_minor) / 100,
      e.reference,
      e.staff_name,
    ]),
  );
  if (format === "xlsx") {
    const { default: ExcelJS } = await import("exceljs");
    const wb = new ExcelJS.Workbook();
    wb.creator = "Booking OS";
    wb.created = new Date();
    const sheet = (name: string, headers: string[], rows: any[][]) => {
      const w = wb.addWorksheet(name, {
        views: [{ state: "frozen", ySplit: 1 }],
      });
      w.addRow(headers);
      for (const r of rows) w.addRow(r);
      w.getRow(1).font = { bold: true, color: { argb: "FFFFFFFF" } };
      w.getRow(1).fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: "FF337418" },
      };
      w.columns.forEach((c) => {
        c.width = 24;
      });
      w.autoFilter = {
        from: { row: 1, column: 1 },
        to: { row: Math.max(1, w.rowCount), column: headers.length },
      };
      w.eachRow((r, i) => {
        if (i > 1)
          r.eachCell((c) => {
            if (typeof c.value === "number")
              c.numFmt = "#,##0.00;[Red]-#,##0.00";
            c.alignment = { vertical: "top", wrapText: true };
          });
      });
      return w;
    };
    sheet("Summary", ["Metric", `Value (${d.currency})`], summary);
    sheet(
      "Bookings",
      [
        "Reference",
        "Customer",
        "Business",
        "Space",
        "Booking start (UTC)",
        "Status",
        "Subtotal",
        "Discount",
        "Final tariff",
        "Received this period (net)",
        "Cash (net)",
        "UPI (net)",
        "Card (net)",
        "Bank transfer (net)",
        "Received to cutoff (net)",
        "Outstanding",
      ],
      bookingRows,
    );
    sheet(
      "Account movements",
      [
        "Transaction",
        "Local time",
        "Type",
        "Booking",
        "Business",
        "Space",
        "Category",
        "Reason",
        "Account",
        "Method",
        "Signed amount",
        "Reference",
        "Recorded by",
      ],
      txRows,
    );
    sheet(
      "Income and expenses",
      [
        "Transaction",
        "Local time",
        "Type",
        "Booking",
        "Business",
        "Space",
        "Category",
        "Reason",
        "Account",
        "Method",
        "Signed amount",
        "Reference",
        "Recorded by",
      ],
      txRows.filter((r: any[]) =>
        ["income", "expense", "reversal"].includes(r[2]),
      ),
    );
    sheet(
      "Monthly totals",
      ["Month", "Income", "Expenses"],
      d.trend.map((r: Row) => [
        r.month,
        r.income_minor / 100,
        r.expenses_minor / 100,
      ]),
    );
    sheet(
      "Account balances",
      [
        "Account",
        "Opening balance at period start",
        "Closing balance at period end",
        "Account opening date",
      ],
      d.account_statement.map((a: Row) => [
        a.name,
        a.opening_minor / 100,
        a.closing_minor / 100,
        new Date(a.opening_at).toISOString(),
      ]),
    );
    return Buffer.from(await wb.xlsx.writeBuffer());
  }
  const { default: PDFDocument } = await import("pdfkit");
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
        size: "A4",
        font: reportFont(),
        margin: 44,
        bufferPages: true,
        info: {
          Title: `Booking OS ${label(type)} report`,
          Author: "Booking OS",
        },
      }),
      chunks: Buffer[] = [];
    doc.on("data", (c) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);
    doc.registerFont("Report", reportFont());
    doc.font("Report");
    const safe = (v: any) => String(v ?? "");
    const line = (text: string, size = 10) => {
      doc
        .fontSize(size)
        .fillColor("#202020")
        .text(safe(text), { width: 507, lineGap: 3 });
    };
    const section = (text: string) => {
      if (doc.y > 640) doc.addPage();
      doc.moveDown(0.6);
      doc.font("Report").fillColor("#337418").fontSize(13).text(text);
      doc.font("Report").moveDown(0.4);
    };
    doc.font("Report").fillColor("#337418").fontSize(23).text("BOOKING OS");
    doc.moveDown(0.4);
    line(d.name, 17);
    line(`${label(type).toUpperCase()} REPORT`, 12);
    line(`${d.from} to ${d.until} | ${d.timezone}`);
    line(`Currency: ${d.currency}`);
    line(
      `Business: ${d.scope_business ?? "All businesses"} | Space: ${d.scope_space ?? "All spaces"}`,
      8,
    );
    section("Period summary");
    for (const [k, v] of summary.slice(7))
      line(`${k}: ${money(Number(v) * 100, d.currency)}`);
    section("Monthly totals");
    if (!d.trend.length) line("No income or expenses in this period.");
    for (const r of d.trend)
      line(
        `${r.month} | Income ${money(r.income_minor, d.currency)} | Expenses ${money(r.expenses_minor, d.currency)}`,
      );
    section("Booking collections");
    line(
      "Tariff is booking value. Received this period follows payment dates; refunds are deducted.",
    );
    for (const b of d.bookings) {
      if (doc.y > 620) doc.addPage();
      doc.moveDown(0.5);
      doc.font("Report");
      line(`${b.reference} | ${b.business} | ${b.space}`, 11);
      doc.font("Report");
      line(`Customer: ${b.customer} | Status: ${b.status}`);
      line(
        `Booking: ${new Date(b.starts_at).toISOString()} | Tariff: ${money(b.total_minor, d.currency)}`,
      );
      if (b.price_snapshot?.discount_minor) {
        line(
          `Subtotal: ${money(b.price_snapshot.subtotal_minor, d.currency)} | Discount: ${money(b.price_snapshot.discount_minor, d.currency)}`,
        );
        if (b.price_snapshot.selection?.discount?.reason)
          line(
            `Discount reason: ${b.price_snapshot.selection.discount.reason}`,
          );
      }
      const net = b.payments.reduce(
        (n: number, p: Row) =>
          n + (p.kind === "collection" ? 1 : -1) * p.amount_minor,
        0,
      );
      line(
        `Received this period (net): ${money(net, d.currency)} | Received to cutoff: ${money(b.received_to_date_minor, d.currency)}`,
      );
      for (const p of b.payments)
        line(
          `${p.kind === "refund" ? "Refund" : "Received"} ${money(p.amount_minor, d.currency)} as ${label(p.method)} | ${new Date(p.received_at).toISOString()}`,
          9,
        );
      line(
        `Outstanding at cutoff: ${money(Math.max(0, (b.status === "cancelled" ? 0 : b.total_minor) - b.received_to_date_minor), d.currency)}`,
      );
    }
    if (!d.bookings.length) line("No matching bookings.");
    section("All transactions and account movements");
    if (!d.transactions.length) line("No transactions in this period.");
    for (const e of d.transactions) {
      if (doc.y > 650) doc.addPage();
      doc.moveDown(0.4);
      doc.font("Report");
      line(
        `${e.local_time} | ${label(e.kind)} | ${e.booking_reference ?? e.category}`,
        10,
      );
      doc.font("Report");
      line(
        `${e.business_name ?? "Shared / organization"}${e.space_name ? " / " + e.space_name : ""} | ${e.reason}`,
        9,
      );
      for (const l of e.lines)
        line(
          `${l.account_name} | ${label(l.method)} | ${money(Number(l.amount_minor), d.currency)}`,
          9,
        );
      line(
        `Recorded by: ${e.staff_name} | Reference: ${e.reference || "-"}`,
        8,
      );
    }
    section("Account balances - whole organization");
    line(
      "Balances follow recorded entries and opening dates. Transfers do not count as income or expenses.",
    );
    for (const a of d.account_statement)
      line(
        `${a.name} | Opening ${money(a.opening_minor, d.currency)} | Closing ${money(a.closing_minor, d.currency)} | Opening date ${new Date(a.opening_at).toISOString().slice(0, 10)}`,
      );
    const range = doc.bufferedPageRange();
    for (let i = 0; i < range.count; i++) {
      doc.switchToPage(i);
      doc
        .fontSize(8)
        .fillColor("#666666")
        .text(
          `Booking OS | Recorded accounts | Page ${i + 1} of ${range.count}`,
          44,
          805,
          { lineBreak: false },
        );
    }
    doc.end();
  });
}
