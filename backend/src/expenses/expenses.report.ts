import PDFDocument from "pdfkit";
import ExcelJS from "exceljs";
import { reportFont } from "../accounts/report-font";
type Row = Record<string, any>;
export async function renderExpenseReport(
  d: Row,
  format: string,
): Promise<Buffer> {
  const money = (n: unknown) =>
    `${d.currency === "INR" ? "₹" : d.currency} ${(Number(n) / 100).toFixed(2)}`;
  const summary = [
    ["Organization", d.name],
    ["Period", `${d.from} to ${d.until}`],
    ["Timezone", d.timezone],
    ["Category", d.category_filter ?? "All categories"],
    ["Business", d.business_filter ?? "All businesses"],
    ["Space", d.space_filter ?? "All spaces"],
    ["Account filter", d.account_filter ?? "All accounts"],
    ["Search", d.search_filter || "None"],
    ["Net expenses", Number(d.total_minor) / 100],
    ["Entries", d.count],
  ];
  const payments = d.items.flatMap((r: Row) =>
    (r.lines ?? []).map((l: Row) => [
      r.id,
      r.local_date,
      r.kind,
      r.reverses_id ?? "",
      r.category_name,
      r.reason,
      l.account_name,
      l.method,
      -Number(l.amount_minor) / 100,
    ]),
  );
  if (format === "xlsx") {
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
      "Categories",
      ["Category", `Net expenses (${d.currency})`],
      d.categories.map((c: Row) => [c.name, Number(c.total_minor) / 100]),
    );
    sheet(
      "Expenses",
      [
        "ID",
        "Date",
        "Type",
        "Original expense",
        "Category",
        "Reason",
        "Business",
        "Space",
        `Amount (${d.currency})`,
        "Reference",
        "Recorded by",
        "Invoices",
      ],
      d.items.map((r: Row) => [
        r.id,
        r.local_date,
        r.kind,
        r.reverses_id ?? "",
        r.category_name,
        r.reason,
        r.business_name ?? "Organization",
        r.space_name ?? "",
        Number(r.amount_minor) / 100,
        r.reference,
        r.staff_name,
        r.attachments_count,
      ]),
    );
    sheet(
      "Payment breakdown",
      [
        "Expense ID",
        "Date",
        "Type",
        "Original expense",
        "Category",
        "Reason",
        "Account",
        "Method",
        `Expense amount (${d.currency})`,
      ],
      payments,
    );
    return Buffer.from(await wb.xlsx.writeBuffer());
  }
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
        size: "A4",
        margin: 44,
        font: reportFont(),
        bufferPages: true,
        info: { Title: "Booking OS Expense report" },
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
    doc.fontSize(24).fillColor("#337418").text("Expense report");
    doc.moveDown(0.5);
    for (const [k, v] of summary)
      line(`${k}: ${k === "Net expenses" ? money(d.total_minor) : v}`);
    line(
      "Reversals reduce expenses on their recorded date. Transfers are excluded.",
      9,
    );
    section("Category breakdown");
    for (const c of d.categories) line(`${c.name}: ${money(c.total_minor)}`);
    section("Expense details");
    if (!d.items.length) line("No expenses match this period and filters.");
    for (const r of d.items) {
      if (doc.y > 610) doc.addPage();
      line(
        `${r.local_date} · ${r.category_name} · ${money(r.amount_minor)}`,
        12,
      );
      line(`${r.kind === "reversal" ? "REVERSAL · " : ""}${r.reason}`);
      line(
        `${r.business_name ?? "Organization"}${r.space_name ? " / " + r.space_name : ""}`,
        9,
      );
      for (const l of r.lines ?? [])
        line(
          `${l.account_name} · ${l.method === "upi" ? "UPI" : l.method.replaceAll("_", " ")} · ${money(-Number(l.amount_minor))}`,
          9,
        );
      line(
        `ID: ${r.id}${r.reverses_id ? " | Original: " + r.reverses_id : ""}`,
        8,
      );
      line(
        `Reference: ${r.reference || "-"} · Recorded by: ${r.staff_name} · Invoices: ${r.attachments_count}`,
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
