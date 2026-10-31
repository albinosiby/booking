import { reportFont } from "../accounts/report-font";
type Row = Record<string, any>;
const dateLabel = (value: string) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) return value;
  const months = [
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
  return `${match[3]} ${months[Number(match[2]) - 1]} ${match[1]}`;
};
const dateTimeLabel = (value: string) => {
  const match = /^(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2})/.exec(value);
  if (!match) return dateLabel(value);
  const hour = Number(match[2]);
  return `${dateLabel(match[1])}, ${hour % 12 || 12}:${match[3]} ${hour < 12 ? "AM" : "PM"}`;
};
const exportedLabel = (d: Row) =>
  `${new Intl.DateTimeFormat("en-GB", {
    timeZone: d.timezone || "UTC",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  })
    .format(new Date(d.exported_at ?? Date.now()))
    .replace(/[\u202f\u00a0]/g, " ")} (${d.timezone || "UTC"})`;
const methodLabel = (value: string) =>
  value === "upi"
    ? "UPI"
    : value
        .replaceAll("_", " ")
        .replace(/^./, (letter) => letter.toUpperCase());
export async function renderExpenseReport(
  d: Row,
  format: string,
): Promise<Buffer> {
  const numberText = (n: unknown) =>
    new Intl.NumberFormat("en-IN", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(Number(n) / 100);
  const money = (n: unknown) =>
    `${d.currency === "INR" ? "₹" : d.currency} ${numberText(n)}`;
  const cashMinor = d.items.reduce(
    (total: number, r: Row) =>
      total +
      (r.lines ?? []).reduce(
        (sum: number, l: Row) =>
          sum + (l.method === "cash" ? -Number(l.amount_minor) : 0),
        0,
      ),
    0,
  );
  const bankMinor = d.items.reduce(
    (total: number, r: Row) =>
      total +
      (r.lines ?? []).reduce(
        (sum: number, l: Row) =>
          sum + (l.method !== "cash" ? -Number(l.amount_minor) : 0),
        0,
      ),
    0,
  );
  const summary = [
    ["Organization", d.name],
    ["Period", `${d.from} to ${d.until}`],
    ["Exported at", exportedLabel(d)],
    ["Timezone", d.timezone],
    ["Category", d.category_filter ?? "All categories"],
    ["Business", d.business_filter ?? "All businesses"],
    ["Space", d.space_filter ?? "All spaces"],
    ["Account filter", d.account_filter ?? "All accounts"],
    ["Search", d.search_filter || "None"],
    ["Gross expenses", Number(d.gross_minor ?? d.total_minor) / 100],
    ["Reversals", Number(d.reversals_minor ?? 0) / 100],
    ["Net expenses", Number(d.total_minor) / 100],
    ["Net cash spent", cashMinor / 100],
    ["Net bank spent", bankMinor / 100],
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
  const { default: PDFDocument } = await import("pdfkit");
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
        size: "A4",
        layout: "landscape",
        margin: 40,
        font: reportFont(),
        bufferPages: true,
        info: { Title: "Booking OS Expense report" },
      }),
      chunks: Buffer[] = [];
    doc.on("data", (c) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);
    const left = doc.page.margins.left;
    const width = doc.page.width - left - doc.page.margins.right;
    const bottom = doc.page.height - 55;
    const ink = "#23322B",
      green = "#246B3A",
      subtle = "#617067";
    const clean = (value: unknown) =>
      String(value ?? "")
        .replace(/\s+/g, " ")
        .trim();
    const splitCell = (value: unknown) =>
      clean(value).match(/.{1,120}/gu) ?? [""];
    doc.rect(left, 40, width, 91).fill("#EDF5EE");
    doc
      .fillColor(green)
      .fontSize(20)
      .text("Expense report", left + 14, 48, { width: width - 28 });
    doc
      .fillColor(ink)
      .fontSize(10)
      .text(clean(d.name), left + 14, 76, { width: width - 28 });
    doc
      .fillColor(subtle)
      .fontSize(8.5)
      .text(
        `${dateLabel(d.from)} to ${dateLabel(d.until)}  |  ${d.category_filter ?? "All expenses"}  |  ${d.space_filter ?? "All spaces"}`,
        left + 14,
        96,
        { width: width - 28 },
      );
    doc
      .fillColor(subtle)
      .fontSize(8.5)
      .text(`Exported ${exportedLabel(d)}`, left + 14, 113, {
        width: width - 28,
      });
    const totals = [
      ["Gross expenses", money(d.gross_minor ?? d.total_minor)],
      ["Reversals", money(d.reversals_minor ?? 0)],
      ["Net spent", money(d.total_minor)],
      ["Net cash", money(cashMinor)],
      ["Net bank / digital", money(bankMinor)],
    ];
    const column = width / totals.length;
    totals.forEach(([label, value], index) => {
      const x = left + index * column;
      doc
        .fillColor(subtle)
        .fontSize(8)
        .text(label, x, 143, { width: column - 10 });
      doc
        .fillColor(ink)
        .fontSize(11)
        .text(value, x, 158, { width: column - 10 });
    });
    doc
      .fillColor(subtle)
      .fontSize(8)
      .text(
        `Business: ${d.business_filter ?? "All"}  |  Account: ${d.account_filter ?? "All"}${d.search_filter ? `  |  Search: ${d.search_filter}` : ""}  |  ${d.count} entries`,
        left,
        183,
        { width },
      );
    doc.y = Math.max(doc.y, 207);
    const table = (
      title: string,
      headers: string[],
      widths: number[],
      rows: string[][],
      rightAligned: number[] = [],
    ) => {
      const tableWidth = widths.reduce((n, w) => n + w, 0);
      const headerHeight = 26;
      let y = doc.y;
      const heading = (continued = false) => {
        if (y + 57 > bottom) {
          doc.addPage();
          y = doc.page.margins.top;
        }
        doc
          .fillColor(green)
          .fontSize(11)
          .text(`${title}${continued ? " (continued)" : ""}`, left, y, {
            width,
          });
        y += 23;
        doc.rect(left, y, tableWidth, headerHeight).fill(green);
        let x = left;
        headers.forEach((header, i) => {
          doc
            .fillColor("#FFFFFF")
            .fontSize(8)
            .text(header, x + 6, y + 7, {
              width: widths[i] - 10,
              height: headerHeight - 8,
              align: "left",
            });
          x += widths[i];
        });
        y += headerHeight;
      };
      heading();
      if (rows.length === 0) {
        doc
          .fillColor(subtle)
          .fontSize(9)
          .text(
            "No expenses match this period and filters.",
            left + 7,
            y + 10,
            { width: tableWidth - 14 },
          );
        y = doc.y + 14;
      }
      rows.forEach((cells, rowIndex) => {
        const segments = cells.map(splitCell);
        const segmentCount = Math.max(...segments.map((parts) => parts.length));
        for (let segment = 0; segment < segmentCount; segment++) {
          const cellText = segments.map((parts) => parts[segment] ?? "");
          const heights = cellText.map((cell, i) => {
            doc.fontSize(8.4);
            return doc.heightOfString(cell, {
              width: widths[i] - 12,
              lineGap: 1,
            });
          });
          const rowHeight = Math.max(
            25,
            ...heights.map((height) => height + 10),
          );
          if (y + rowHeight > bottom) {
            doc.addPage();
            y = doc.page.margins.top;
            heading(true);
          }
          doc
            .rect(left, y, tableWidth, rowHeight)
            .fill(rowIndex % 2 ? "#F7FAF7" : "#FFFFFF");
          let x = left;
          cellText.forEach((cell, i) => {
            doc
              .fillColor(ink)
              .fontSize(8.4)
              .text(cell, x + 6, y + 5, {
                width: widths[i] - 12,
                height: rowHeight - 9,
                lineGap: 1,
                align: rightAligned.includes(i) ? "right" : "left",
              });
            x += widths[i];
          });
          doc
            .moveTo(left, y + rowHeight)
            .lineTo(left + tableWidth, y + rowHeight)
            .strokeColor("#DCE5DD")
            .lineWidth(0.5)
            .stroke();
          y += rowHeight;
        }
      });
      doc.y = y + 18;
    };
    table(
      "Expense details",
      [
        "Date",
        "Category",
        "Reason",
        "Space",
        `Cash (${d.currency})`,
        `Bank / digital (${d.currency})`,
        `Net total (${d.currency})`,
      ],
      [80, 105, 190, 110, 90, 90, width - 665],
      d.items.map((r: Row) => {
        const cash = (r.lines ?? []).reduce(
          (n: number, l: Row) =>
            n + (l.method === "cash" ? -Number(l.amount_minor) : 0),
          0,
        );
        const bank = (r.lines ?? []).reduce(
          (n: number, l: Row) =>
            n + (l.method !== "cash" ? -Number(l.amount_minor) : 0),
          0,
        );
        return [
          dateLabel(String(r.local_date ?? "")),
          `${r.category_name}${r.kind === "reversal" ? " reversal" : ""}`,
          clean(r.reason),
          clean(r.space_name || r.business_name || "Organization"),
          numberText(cash),
          numberText(bank),
          numberText(r.amount_minor),
        ];
      }),
      [4, 5, 6],
    );
    table(
      "Payment details",
      [
        "Payment date / time",
        "Category / reason",
        "Method",
        "Account",
        `Amount (${d.currency})`,
        "Reference / audit",
      ],
      [121, 172, 82, 103, 97, width - 575],
      d.items.flatMap((r: Row) =>
        (r.lines ?? []).map((line: Row) => [
          dateTimeLabel(String(r.local_time || r.local_date || "")),
          `${r.category_name} - ${r.reason}`,
          `${methodLabel(String(line.method))}${r.kind === "reversal" ? " reversal" : ""}`,
          clean(line.account_name),
          numberText(-Number(line.amount_minor)),
          [
            r.reference ? `Ref: ${r.reference}` : "",
            `By: ${r.staff_name || "Unknown"}`,
            `Invoices: ${r.attachments_count ?? 0}`,
            `ID: ${r.id}`,
            r.reverses_id ? `Original: ${r.reverses_id}` : "",
          ]
            .filter(Boolean)
            .join(" | "),
        ]),
      ),
      [4],
    );
    if (doc.y + 28 > bottom) doc.addPage();
    doc
      .fillColor(subtle)
      .fontSize(7.5)
      .text(
        "Bank / digital includes UPI, card and bank transfers. Reversals reduce spending on the date recorded. Transfers between accounts are excluded.",
        left,
        doc.y,
        { width },
      );
    const range = doc.bufferedPageRange();
    for (let i = 0; i < range.count; i++) {
      doc.switchToPage(i);
      doc
        .fontSize(8)
        .fillColor(subtle)
        .text(
          `Booking OS  |  Exported ${exportedLabel(d)}  |  Page ${i + 1} of ${range.count}`,
          left,
          doc.page.height - 29,
          {
            lineBreak: false,
            height: 12,
            width,
            align: "right",
          },
        );
    }
    doc.end();
  });
}
