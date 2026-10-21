import { reportFont } from "../accounts/report-font";
type Row = Record<string, any>;
export async function renderIncomeReport(
  d: Row,
  format: string,
): Promise<Buffer> {
  const money = (n: unknown) =>
    `${d.currency === "INR" ? "₹" : d.currency} ${(Number(n) / 100).toFixed(2)}`;
  const method = (m: string) => (m === "upi" ? "UPI" : m.replaceAll("_", " "));
  const summary: [string, unknown][] = [
    ["Organization", d.name],
    ["Period", `${d.from} to ${d.until}`],
    ["Timezone", d.timezone],
    ["Source", d.source_filter ?? "All sources"],
    ["Business", d.business_filter ?? "All businesses"],
    ["Space", d.space_filter ?? "All spaces"],
    ["Account filter", d.account_filter ?? "All accounts"],
    ["Search", d.search_filter || "None"],
    ["Total income", Number(d.total_minor) / 100],
    ["Refunds", Number(d.refunds_minor) / 100],
    ["Net income", Number(d.net_minor) / 100],
    ["Entries", d.count],
  ];
  const payments = d.items.flatMap((r: Row) =>
    (r.lines ?? []).map((l: Row) => [
      r.id,
      r.local_date,
      r.kind,
      r.reverses_id ?? "",
      r.source_name,
      r.booking_reference ?? "",
      l.account_name,
      method(l.method),
      Number(l.amount_minor) / 100,
    ]),
  );
  if (format === "xlsx") {
    const { default: ExcelJS } = await import("exceljs");
    const wb = new ExcelJS.Workbook();
    wb.creator = "Booking OS";
    const sheet = (name: string, headers: string[], rows: unknown[][]) => {
      const s = wb.addWorksheet(name, {
        views: [{ state: "frozen", ySplit: 1 }],
      });
      s.addRow(headers);
      rows.forEach((r) => s.addRow(r));
      s.getRow(1).font = { bold: true, color: { argb: "FFFFFFFF" } };
      s.getRow(1).fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: "FF337418" },
      };
      s.columns.forEach((c) => (c.width = 25));
      s.eachRow((r, i) => {
        if (i > 1)
          r.eachCell((c) => {
            c.alignment = { wrapText: true, vertical: "top" };
            if (typeof c.value === "number")
              c.numFmt = "#,##0.00;[Red]-#,##0.00";
          });
      });
      s.autoFilter = {
        from: { row: 1, column: 1 },
        to: { row: s.rowCount, column: headers.length },
      };
    };
    sheet("Summary", ["Metric", `Value (${d.currency})`], summary);
    sheet(
      "Sources",
      ["Source", `Income (${d.currency})`],
      d.sources.map((s: Row) => [s.name, Number(s.total_minor) / 100]),
    );
    sheet(
      "Income",
      [
        "ID",
        "Date",
        "Type",
        "Original entry",
        "Source",
        "Booking or admission",
        "Customer",
        "Reason",
        "Business",
        "Space",
        `Amount (${d.currency})`,
        "Reference",
        "Recorded by",
      ],
      d.items.map((r: Row) => [
        r.id,
        r.local_date,
        r.kind,
        r.reverses_id ?? "",
        r.source_name,
        r.booking_reference ?? "",
        r.customer_name ?? "",
        r.reason,
        r.business_name ?? "Organization",
        r.space_name ?? "",
        Number(r.amount_minor) / 100,
        r.reference,
        r.staff_name,
      ]),
    );
    sheet(
      "Payment breakdown",
      [
        "Entry ID",
        "Date",
        "Type",
        "Original entry",
        "Source",
        "Booking or admission",
        "Account",
        "Method",
        `Amount (${d.currency})`,
      ],
      payments,
    );
    return Buffer.from(await wb.xlsx.writeBuffer());
  }
  const { default: PDFDocument } = await import("pdfkit");
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
        size: "A4",
        margin: 44,
        font: reportFont(),
        bufferPages: true,
        info: { Title: "Booking OS Income report" },
      }),
      chunks: Buffer[] = [];
    doc.on("data", (c) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);
    const line = (s: string, size = 10) => {
      doc
        .fontSize(size)
        .fillColor("#202020")
        .text(s, { width: 507, lineGap: 3 });
    };
    const section = (s: string) => {
      if (doc.y > 660) doc.addPage();
      doc.moveDown().fontSize(14).fillColor("#337418").text(s);
      doc.moveDown(0.4);
    };
    const amounts = new Set(["Total income", "Refunds", "Net income"]);
    doc.fontSize(24).fillColor("#337418").text("Income report");
    doc.moveDown(0.5);
    for (const [k, v] of summary)
      line(`${k}: ${amounts.has(k) ? money(Number(v) * 100) : v}`);
    line(
      "Income is booking and admission payments plus extra income. Refunds are listed separately; reversals reduce income on their recorded date. Transfers are excluded.",
      9,
    );
    section("Source breakdown");
    for (const s of d.sources) line(`${s.name}: ${money(s.total_minor)}`);
    section("Income details");
    if (!d.items.length) line("No income matches this period and filters.");
    for (const r of d.items) {
      if (doc.y > 610) doc.addPage();
      line(`${r.local_date} · ${r.source_name} · ${money(r.amount_minor)}`, 12);
      line(
        `${r.kind === "reversal" ? "REVERSAL · " : r.is_refund ? "REFUND · " : ""}${r.booking_reference ? r.booking_reference + " · " : ""}${r.customer_name ? r.customer_name + " · " : ""}${r.reason}`,
      );
      line(
        `${r.business_name ?? "Organization"}${r.space_name ? " / " + r.space_name : ""}`,
        9,
      );
      for (const l of r.lines ?? [])
        line(
          `${l.account_name} · ${method(l.method)} · ${money(l.amount_minor)}`,
          9,
        );
      line(
        `ID: ${r.id}${r.reverses_id ? " | Original: " + r.reverses_id : ""}`,
        8,
      );
      line(
        `Reference: ${r.reference || "-"} · Recorded by: ${r.staff_name}`,
        8,
      );
      doc.moveDown(0.7);
    }
    const range = doc.bufferedPageRange();
    for (let i = 0; i < range.count; i++) {
      doc.switchToPage(i);
      doc
        .fontSize(8)
        .fillColor("#666666")
        .text(`Booking OS · Page ${i + 1} of ${range.count}`, 44, 805, {
          lineBreak: false,
        });
    }
    doc.end();
  });
}
