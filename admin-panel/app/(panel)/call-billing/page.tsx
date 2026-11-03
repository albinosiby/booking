import { admin } from "../../../lib/api";
import { date, rupeeInput, rupees as money } from "../../../lib/format";
import { PageHeader } from "../../../components/ui";
import { ActionForm } from "../../../features/call-service/action-form";
import { saveBillingDefaults } from "../../../features/call-wallet/actions";

type Defaults = {
  rate_paise_per_minute: number | null;
  plans_paise: number[];
  custom_enabled: boolean;
  custom_above_paise: number;
  custom_max_paise: number;
  low_balance_paise: number;
  version: number;
  updated_by: string;
  updated_at: string;
  gateway_configured: boolean;
};

export default async function CallBilling() {
  const d = await admin<Defaults>("/call-billing");
  return (
    <>
      <PageHeader
        title="Call billing"
        description="Default call pricing and recharge plans for every client. Set a different price for one client on their organization page."
      />
      {d.rate_paise_per_minute == null && (
        <p role="alert" className="info-note">
          No rate is set yet. Clients cannot recharge, and calls are recorded
          at ₹0 until you save a rate.
        </p>
      )}
      {!d.gateway_configured && (
        <p className="info-note">
          The payment gateway is not configured on the booking API, so online
          recharge stays off. You can still add balance by hand.
        </p>
      )}
      <div className="two">
        <ActionForm action={saveBillingDefaults}>
          <h2>Default pricing</h2>
          <input type="hidden" name="version" value={d.version} />
          <label>
            Per-minute rate (₹)
            <input
              name="rate"
              inputMode="decimal"
              defaultValue={rupeeInput(d.rate_paise_per_minute)}
              placeholder="10.80"
              required
            />
            <small>Each started minute of a call is charged at this rate.</small>
          </label>
          <label>
            Recharge plans (₹)
            <input
              name="plans"
              defaultValue={d.plans_paise.map((p) => rupeeInput(p)).join(", ")}
              placeholder="250, 500, 750, 1000"
              required
            />
            <small>
              1 to 6 amounts, separated by commas. Each from ₹100 to ₹50,000.
            </small>
          </label>
          <fieldset>
            <legend>Custom amount</legend>
            <label>
              <input
                type="checkbox"
                name="custom_enabled"
                defaultChecked={d.custom_enabled}
                style={{ width: "auto", marginRight: 8 }}
              />
              Let clients enter their own amount
            </label>
            <div className="two">
              <label>
                Allowed above (₹)
                <input
                  name="custom_above"
                  inputMode="decimal"
                  defaultValue={rupeeInput(d.custom_above_paise)}
                  placeholder="1000"
                />
                <small>Clients must enter more than this.</small>
              </label>
              <label>
                Maximum (₹)
                <input
                  name="custom_max"
                  inputMode="decimal"
                  defaultValue={rupeeInput(d.custom_max_paise)}
                  placeholder="50000"
                  required
                />
              </label>
            </div>
          </fieldset>
          <label>
            Low-balance alert below (₹)
            <input
              name="low_balance"
              inputMode="decimal"
              defaultValue={rupeeInput(d.low_balance_paise)}
              placeholder="250"
            />
            <small>
              Owners get one push notification when the balance drops below
              this, and another at ₹0. Use 0 to send only the ₹0 alert.
            </small>
          </label>
          <div>
            <button>Save default pricing</button>
          </div>
        </ActionForm>
        <div className="card">
          <h2>What clients see</h2>
          <dl className="kv">
            <dt>Rate</dt>
            <dd>
              {d.rate_paise_per_minute == null
                ? "Not set"
                : `${money(d.rate_paise_per_minute)} per minute`}
            </dd>
            <dt>Plans</dt>
            <dd>{d.plans_paise.map((p) => money(p)).join(" · ")}</dd>
            <dt>Custom amount</dt>
            <dd>
              {d.custom_enabled
                ? `More than ${money(d.custom_above_paise)}, up to ${money(d.custom_max_paise)}`
                : "Off: plans only"}
            </dd>
            <dt>Low-balance alert</dt>
            <dd>
              {d.low_balance_paise
                ? `Below ${money(d.low_balance_paise)}`
                : "Only at ₹0"}
            </dd>
            <dt>Last changed</dt>
            <dd>
              {d.updated_by
                ? `${date(d.updated_at)} by ${d.updated_by}`
                : "Never"}
            </dd>
          </dl>
          <p className="sub">
            A new rate applies to calls charged after you save it. Charges
            already in a client&apos;s history keep the rate they used.
          </p>
        </div>
      </div>
    </>
  );
}
