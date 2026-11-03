import Link from "next/link";
import { randomUUID } from "node:crypto";
import { admin } from "../../lib/api";
import { date, label, rupeeInput, rupees as money } from "../../lib/format";
import { Badge } from "../../components/ui";
import { ActionForm } from "../call-service/action-form";
import { adjustWallet, saveClientPricing } from "./actions";

type Pricing = {
  rate_paise_per_minute: number | null;
  plans_paise: number[];
  custom_enabled: boolean;
  custom_above_paise: number;
  custom_max_paise: number;
  low_balance_paise: number;
};
type Wallet = {
  balance_paise: number;
  minutes_left: number;
  low_alert_sent: boolean;
  totals: {
    recharged_paise: number;
    added_paise: number;
    free_paise: number;
    deducted_paise: number;
    spent_paise: number;
    call_seconds: number;
    calls: number;
  };
  effective: Pricing & { custom_min_paise: number };
  overrides: Partial<Pricing>;
  defaults: Pricing;
  orders: {
    order_id: string;
    amount_paise: number;
    status: string;
    payment_method: string | null;
    created_at: string;
    paid_at: string | null;
  }[];
  ledger: {
    id: string;
    kind: string;
    amount_paise: number;
    balance_after_paise: number;
    reference: string;
    call_seconds: number | null;
    rate_paise_per_minute: number | null;
    payment_method: string;
    external_reference: string;
    note: string;
    admin_email: string;
    created_at: string;
  }[];
  next_offset: number | null;
};

const MODES = [
  ["cash", "Cash"],
  ["upi", "UPI"],
  ["bank_transfer", "Bank transfer"],
  ["cheque", "Cheque"],
  ["other", "Other"],
];
const minutes = (s: number) => `${Math.round(s / 60).toLocaleString("en-IN")} min`;
const talk = (s: number) =>
  s < 60 ? `${s}s` : `${Math.floor(s / 60)}m${s % 60 ? ` ${s % 60}s` : ""}`;
const plansText = (p: number[]) => p.map((x) => rupeeInput(x)).join(", ");

function entryLabel(e: Wallet["ledger"][number]) {
  if (e.kind === "call_charge")
    return `Call · ${e.call_seconds == null ? "" : talk(e.call_seconds)}${
      e.rate_paise_per_minute ? ` at ${money(e.rate_paise_per_minute)}/min` : ""
    }`;
  if (e.kind === "recharge")
    return `Online recharge${e.payment_method ? ` · ${e.payment_method.toUpperCase()}` : ""}`;
  if (e.kind === "adjustment")
    return e.amount_paise < 0
      ? "Deducted by admin"
      : e.payment_method
        ? `Added by admin · ${label(e.payment_method)}`
        : "Free credit by admin";
  return label(e.kind);
}

/** Balance, history, client pricing and manual credit for one organization. */
export async function WalletSection({
  org,
  offset,
}: {
  org: string;
  offset: number;
}) {
  const w = await admin<Wallet>(
    `/organizations/${org}/call-wallet?offset=${offset}`,
  );
  const e = w.effective,
    o = w.overrides,
    d = w.defaults;
  const custom = (key: keyof Pricing) =>
    key in o ? <Badge value="custom" /> : null;
  return (
    <section id="call-wallet" style={{ display: "grid", gap: 22 }}>
      <h2>Call wallet</h2>
      <div className="grid">
        <div className="stat">
          <b>{money(w.balance_paise)}</b>
          <span>
            Balance · about {w.minutes_left} min
            {w.balance_paise < e.low_balance_paise ? " · low" : ""}
          </span>
        </div>
        <div className="stat">
          <b>{money(w.totals.recharged_paise)}</b>
          <span>Recharged online</span>
        </div>
        <div className="stat">
          <b>{money(w.totals.added_paise - w.totals.deducted_paise)}</b>
          <span>
            Added by admin (net)
            {w.totals.free_paise > 0
              ? ` · ${money(w.totals.free_paise)} free`
              : ""}
          </span>
        </div>
        <div className="stat">
          <b>{money(w.totals.spent_paise)}</b>
          <span>
            Spent on {w.totals.calls} calls · {minutes(w.totals.call_seconds)}
          </span>
        </div>
      </div>
      <div className="two">
        <ActionForm action={adjustWallet}>
          <h2>Add balance</h2>
          <p className="sub">
            Add money the client paid you directly, give free credit, or fix a
            mistake. It applies straight away and shows in the client&apos;s
            wallet history.
          </p>
          <input type="hidden" name="org" value={org} />
          <input type="hidden" name="request_id" value={randomUUID()} />
          <div className="two">
            <label>
              Action
              <select name="direction" defaultValue="add">
                <option value="add">Add balance (client paid)</option>
                <option value="free">Free credit (not paid)</option>
                <option value="deduct">Deduct (correction)</option>
              </select>
            </label>
            <label>
              Amount (₹)
              <input name="amount" inputMode="decimal" placeholder="1000" required />
            </label>
          </div>
          <div className="two">
            <label>
              Paid by
              <select name="payment_mode" defaultValue="cash">
                {MODES.map(([value, text]) => (
                  <option key={value} value={value}>
                    {text}
                  </option>
                ))}
              </select>
              <small>Only used when the client paid.</small>
            </label>
            <label>
              Receipt or reference
              <input name="external_reference" maxLength={100} placeholder="Optional" />
            </label>
          </div>
          <label>
            Note (the client can see this)
            <input
              name="note"
              maxLength={500}
              placeholder="Required for free credit and deductions"
            />
          </label>
          <label>
            <input
              type="checkbox"
              name="confirm"
              required
              style={{ width: "auto", marginRight: 8 }}
            />
            I have checked the amount. This changes the client&apos;s balance
            straight away.
          </label>
          <div>
            <button>Save to wallet</button>
          </div>
        </ActionForm>
        <ActionForm action={saveClientPricing}>
          <h2>Pricing for this client</h2>
          <p className="sub">
            Leave a field empty to use the default from{" "}
            <Link href="/call-billing">Call billing</Link>.
          </p>
          <input type="hidden" name="org" value={org} />
          <label>
            Per-minute rate (₹) {custom("rate_paise_per_minute")}
            <input
              name="rate"
              inputMode="decimal"
              defaultValue={rupeeInput(o.rate_paise_per_minute)}
              placeholder={
                d.rate_paise_per_minute == null
                  ? "Default not set"
                  : `Default ${rupeeInput(d.rate_paise_per_minute)}`
              }
            />
          </label>
          <label>
            Recharge plans (₹) {custom("plans_paise")}
            <input
              name="plans"
              defaultValue={o.plans_paise ? plansText(o.plans_paise) : ""}
              placeholder={`Default ${plansText(d.plans_paise)}`}
            />
          </label>
          <label>
            Custom amount {custom("custom_enabled")}
            <select
              name="custom_enabled"
              defaultValue={
                o.custom_enabled == null ? "" : o.custom_enabled ? "on" : "off"
              }
            >
              <option value="">
                Use default ({d.custom_enabled ? "on" : "off"})
              </option>
              <option value="on">On</option>
              <option value="off">Off: plans only</option>
            </select>
          </label>
          <div className="two">
            <label>
              Allowed above (₹) {custom("custom_above_paise")}
              <input
                name="custom_above"
                inputMode="decimal"
                defaultValue={rupeeInput(o.custom_above_paise)}
                placeholder={`Default ${rupeeInput(d.custom_above_paise)}`}
              />
            </label>
            <label>
              Maximum (₹) {custom("custom_max_paise")}
              <input
                name="custom_max"
                inputMode="decimal"
                defaultValue={rupeeInput(o.custom_max_paise)}
                placeholder={`Default ${rupeeInput(d.custom_max_paise)}`}
              />
            </label>
          </div>
          <label>
            Low-balance alert below (₹) {custom("low_balance_paise")}
            <input
              name="low_balance"
              inputMode="decimal"
              defaultValue={rupeeInput(o.low_balance_paise)}
              placeholder={`Default ${rupeeInput(d.low_balance_paise)}`}
            />
          </label>
          <p className="sub">
            Now:{" "}
            {e.rate_paise_per_minute == null
              ? "no rate"
              : `${money(e.rate_paise_per_minute)}/min`}{" "}
            · plans {e.plans_paise.map((p) => money(p)).join(", ")} · custom{" "}
            {e.custom_enabled
              ? `${money(e.custom_min_paise)}–${money(e.custom_max_paise)}`
              : "off"}
          </p>
          <div className="row">
            <button>Save client pricing</button>
            {Object.keys(o).length > 0 && (
              <button name="reset" value="1" className="ghost" formNoValidate>
                Reset to default
              </button>
            )}
          </div>
        </ActionForm>
      </div>
      <div className="card scroll">
        <h2>Recharge history</h2>
        <table>
          <thead>
            <tr>
              <th>Started</th>
              <th>Amount</th>
              <th>Status</th>
              <th>Method</th>
              <th>Paid</th>
              <th>Order ID</th>
            </tr>
          </thead>
          <tbody>
            {w.orders.map((r) => (
              <tr key={r.order_id}>
                <td>{date(r.created_at)}</td>
                <td>{money(r.amount_paise)}</td>
                <td>
                  <Badge value={r.status} />
                </td>
                <td>{r.payment_method ? r.payment_method.toUpperCase() : "—"}</td>
                <td>{date(r.paid_at)}</td>
                <td>
                  <code>{r.order_id}</code>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!w.orders.length && <div className="empty">No online recharges yet.</div>}
      </div>
      <div className="card scroll">
        <h2>Wallet history</h2>
        <table>
          <thead>
            <tr>
              <th>When</th>
              <th>Entry</th>
              <th>Amount</th>
              <th>Balance after</th>
              <th>Details</th>
            </tr>
          </thead>
          <tbody>
            {w.ledger.map((r) => (
              <tr key={r.id}>
                <td>{date(r.created_at)}</td>
                <td>{entryLabel(r)}</td>
                <td>
                  {r.amount_paise > 0 ? "+" : ""}
                  {money(r.amount_paise)}
                </td>
                <td>{money(r.balance_after_paise)}</td>
                <td>
                  {[
                    r.external_reference,
                    r.note,
                    r.admin_email && `by ${r.admin_email}`,
                  ]
                    .filter(Boolean)
                    .join(" · ") || "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!w.ledger.length && <div className="empty">No wallet activity yet.</div>}
        <div className="row">
          {offset > 0 && (
            <Link href={`?wallet=${Math.max(0, offset - 50)}#call-wallet`}>
              ← Newer
            </Link>
          )}
          {w.next_offset != null && (
            <Link href={`?wallet=${w.next_offset}#call-wallet`}>Older →</Link>
          )}
        </div>
      </div>
    </section>
  );
}
