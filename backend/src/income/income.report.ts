import { reportFont } from "../accounts/report-font";
type Row = Record<string, any>;

type IncomeGroup = {
  key: string;
  label: string;
  bookingDate: string;
  paymentDates: string[];
  space: string;
  cashMinor: number;
  nonCashMinor: number;
  totalMinor: number;
};

const minor = (value: unknown) => Number(value ?? 0);
const methodLabel = (value: string) =>
  value === "upi"
    ? "UPI"
    : value
        .replaceAll("_", " ")
        .replace(/^./, (letter) => letter.toUpperCase());
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
const exportedLabel = (d: Row) => {
  const timestamp = new Date(d.exported_at ?? Date.now());
  return `${new Intl.DateTimeFormat("en-GB", {
    timeZone: d.timezone || "UTC",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  })
    .format(timestamp)
    .replace(/[\u202f\u00a0]/g, " ")} (${d.timezone || "UTC"})`;
};
const sourceLabel = (r: Row) => {
  const reference = String(r.booking_reference ?? "").replace(/^#/, "");
  if (reference) {
    const customer = String(r.customer_name ?? "").trim();
    return `#${reference}${customer ? ` ${customer}` : ""}`;
  }
  const source = String(r.source_name || "Extra income");
  const reason = String(r.reason || "").trim();
  return `${r.kind === "reversal" ? "Reversal - " : ""}${source}${reason && reason !== source ? ` - ${reason}` : ""}`;
};
function reportTables(items: Row[]) {
  const groups = new Map<string, IncomeGroup>();
  const payments: Row[] = [];
  for (const r of items) {
    const key = r.booking_id
      ? `booking:${r.booking_id}`
      : r.admission_id
        ? `admission:${r.admission_id}`
        : `entry:${r.id}`;
    let group = groups.get(key);
    if (!group) {
      group = {
        key,
        label: sourceLabel(r),
        bookingDate: r.booking_date ? dateLabel(r.booking_date) : "",
        paymentDates: [],
        space: String(r.space_name || r.business_name || "Shared"),
        cashMinor: 0,
        nonCashMinor: 0,
        totalMinor: 0,
      };
      groups.set(key, group);
    }
    const paymentDate = dateLabel(String(r.local_date ?? ""));
    if (paymentDate && !group.paymentDates.includes(paymentDate)) {
      group.paymentDates.push(paymentDate);
    }
    group.totalMinor += minor(r.amount_minor);
    for (const line of r.lines ?? []) {
      const lineAmount = minor(line.amount_minor);
      if (line.method === "cash") group.cashMinor += lineAmount;
      else group.nonCashMinor += lineAmount;
      payments.push({
        localTime: dateTimeLabel(String(r.local_time || r.local_date || "")),
        source: sourceLabel(r),
        method: `${methodLabel(String(line.method))}${r.is_refund ? " refund" : r.kind === "reversal" ? " reversal" : ""}`,
        account: line.account_name || "",
        amountMinor: lineAmount,
        note: [r.reference, r.reason].filter(Boolean).join(" - "),
      });
    }
  }
  return { groups: [...groups.values()], payments };
}
export async function renderIncomeReport(
  d: Row,
  format: string,
): Promise<Buffer> {
  const money = (n: unknown) =>
    `${d.currency === "INR" ? "₹" : d.currency} ${new Intl.NumberFormat(
      "en-IN",
      {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      },
    ).format(Number(n) / 100)}`;
  const method = methodLabel;
  const { groups, payments: paymentRows } = reportTables(d.items);
  const cashMinor = groups.reduce((n, g) => n + g.cashMinor, 0);
  const nonCashMinor = groups.reduce((n, g) => n + g.nonCashMinor, 0);
  const summary: [string, unknown][] = [
    ["Organization", d.name],
    ["Period", `${d.from} to ${d.until}`],
    ["Exported at", exportedLabel(d)],
    ["Timezone", d.timezone],
    ["Source", d.source_filter ?? "All sources"],
    ["Business", d.business_filter ?? "All businesses"],
    ["Space", d.space_filter ?? "All spaces"],
    ["Account filter", d.account_filter ?? "All accounts"],
    ["Search", d.search_filter || "None"],
    ["Total income", Number(d.total_minor) / 100],
    ["Refunds", Number(d.refunds_minor) / 100],
    ["Net income", Number(d.net_minor) / 100],
    ["Cash received (net)", cashMinor / 100],
    ["Bank / digital received (net)", nonCashMinor / 100],
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
      "Bookings and income",
      [
        "Booking / source",
        "Booking date",
        "Payment date(s)",
        "Space",
        `Cash (${d.currency})`,
        `Bank / digital (${d.currency})`,
        `Net total (${d.currency})`,
      ],
      groups.map((g) => [
        g.label,
        g.bookingDate,
        g.paymentDates.join(", "),
        g.space,
        g.cashMinor / 100,
        g.nonCashMinor / 100,
        g.totalMinor / 100,
      ]),
    );
    sheet(
      "Payment details",
      [
        "Payment date / time",
        "Booking / source",
        "Method",
        "Account",
        `Amount (${d.currency})`,
        "Reference / note",
      ],
      paymentRows.map((p) => [
        p.localTime,
        p.source,
        p.method,
        p.account,
        p.amountMinor / 100,
        p.note,
      ]),
    );
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
        layout: "landscape",
        margin: 40,
        font: reportFont(),
        bufferPages: true,
        info: { Title: "Booking OS Income report" },
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
    const moneyText = (n: number) =>
      new Intl.NumberFormat("en-IN", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      }).format(n / 100);
    doc.rect(left, 40, width, 91).fill("#EDF5EE");
    doc
      .fillColor(green)
      .fontSize(20)
      .text("Income report", left + 14, 48, {
        width: width - 28,
      });
    doc
      .fillColor(ink)
      .fontSize(10)
      .text(clean(d.name), left + 14, 76, {
        width: width - 28,
      });
    doc
      .fillColor(subtle)
      .fontSize(8.5)
      .text(
        `${dateLabel(d.from)} to ${dateLabel(d.until)}  |  ${d.source_filter ?? "All income"}  |  ${d.space_filter ?? "All spaces"}`,
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
    doc.y = 143;
    const totals = [
      ["Gross income", money(d.total_minor)],
      ["Refunds", money(d.refunds_minor)],
      ["Net received", money(d.net_minor)],
      ["Net cash", money(cashMinor)],
      ["Net bank / digital", money(nonCashMinor)],
    ];
    const column = width / totals.length;
    totals.forEach(([label, value], index) => {
      const x = left + index * column;
      doc
        .fillColor(subtle)
        .fontSize(8)
        .text(label, x, 143, {
          width: column - 10,
        });
      doc
        .fillColor(ink)
        .fontSize(11)
        .text(value, x, 158, {
          width: column - 10,
        });
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
        headers.forEach((h, i) => {
          doc
            .fillColor("#FFFFFF")
            .fontSize(8)
            .text(h, x + 6, y + 7, {
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
            "No income matches this period and filters.",
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
          const rowHeight = Math.max(25, ...heights.map((h) => h + 10));
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
      "Bookings and income",
      [
        "Booking / source",
        "Booking date",
        "Payment date(s)",
        "Space",
        `Cash (${d.currency})`,
        `Bank / digital (${d.currency})`,
        `Net total (${d.currency})`,
      ],
      [172, 79, 103, 101, 97, 97, width - 649],
      groups.map((g) => [
        g.label,
        g.bookingDate || "-",
        g.paymentDates.join(", "),
        g.space,
        moneyText(g.cashMinor),
        moneyText(g.nonCashMinor),
        moneyText(g.totalMinor),
      ]),
      [4, 5, 6],
    );
    table(
      "Payment details",
      [
        "Payment date / time",
        "Booking / source",
        "Method",
        "Account",
        `Amount (${d.currency})`,
        "Reference / note",
      ],
      [121, 172, 82, 103, 97, width - 575],
      paymentRows.map((p) => [
        p.localTime,
        p.source,
        p.method,
        p.account,
        moneyText(p.amountMinor),
        p.note,
      ]),
      [4],
    );
    if (doc.y + 28 > bottom) doc.addPage();
    doc
      .fillColor(subtle)
      .fontSize(7.5)
      .text(
        "Bank / digital includes UPI, card and bank transfers. Refunds and reversals reduce the net amounts above. Transfers between accounts are excluded.",
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
