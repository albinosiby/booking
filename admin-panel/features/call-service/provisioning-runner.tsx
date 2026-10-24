"use client";
import { useActionState, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import {
  approveProvisioning,
  continueProvisioning,
  type ProvisioningResult,
  type ProvisioningJob,
} from "./provisioning-actions";
const steps: Record<string, string> = {
  create: "Creating agent",
  variables: "Preparing live space data",
  secret: "Configuring private credentials",
  prompt: "Saving booking instructions",
  verify_tools: "Verifying booking tools",
  commit: "Publishing agent version",
  deploy: "Connecting the selected phone number",
  verify_deployment: "Verifying the connection",
  done: "Connected",
};
export function ProvisioningRunner({
  org,
  initial,
  connected,
  templateReady,
  version,
  services,
  numbers,
}: {
  org: string;
  initial: ProvisioningJob;
  connected: boolean;
  templateReady: boolean;
  version: number;
  services: string[];
  numbers: {
    connection_id: string;
    phone_number: string;
    label: string;
    assigned: boolean;
  }[];
}) {
  const [result, approve, pending] = useActionState<
    ProvisioningResult,
    FormData
  >(approveProvisioning, {});
  const [job, setJob] = useState(initial),
    [running, setRunning] = useState(false),
    [error, setError] = useState("");
  const stop = useRef(false);
  const router = useRouter();
  useEffect(() => {
    if (result.job) {
      setJob(result.job);
      setRunning(true);
      setError("");
    }
  }, [result.job]);
  useEffect(() => {
    if (!running) return;
    stop.current = false;
    let cancelled = false;
    async function run() {
      for (let i = 0; i < 20 && !stop.current && !cancelled; i++) {
        let next;
        try {
          next = await continueProvisioning(org);
        } catch {
          setError("Setup stopped. Refresh the page and resume.");
          break;
        }
        if (cancelled) return;
        if (next.error) {
          setError(next.error);
          break;
        }
        if (next.job) {
          setJob(next.job);
          if (next.job.done) {
            router.refresh();
            break;
          }
        }
      }
      if (!cancelled) setRunning(false);
    }
    void run();
    return () => {
      cancelled = true;
      stop.current = true;
    };
  }, [running, org, router]);
  const available = numbers.filter((n) => !n.assigned);
  return (
    <section
      className="card"
      aria-label="Automatic agent setup"
      style={{ display: "grid", gap: 14 }}
    >
      <h2>Automatic agent setup</h2>
      <p>
        Create a separate agent for this organization, configure its booking
        tools, and connect the selected number.
      </p>
      {!connected && (
        <p className="info-note">
          Sarvam authorization is required.{" "}
          <Link href="/agent-requests/mcp">Connect or reconnect Sarvam →</Link>
        </p>
      )}
      {job.automatic ? (
        <>
          <p role="status" aria-live="polite">
            <b>
              {steps[job.step] ??
                (job.step.startsWith("tool_")
                  ? `Configuring tool ${Number(job.step.slice(5)) + 1} of 7`
                  : job.step)}
            </b>
            {running ? "…" : ""}
          </p>
          <p>Phone: {job.phone_number}</p>
          {job.app_id && <small>Agent: {job.app_id}</small>}
          {(error || job.error) && (
            <p role="alert" className="info-note">
              {error || job.error}
            </p>
          )}
          {!job.done && (
            <div className="row">
              <button
                disabled={running || !connected}
                onClick={() => {
                  setError("");
                  setRunning(true);
                }}
              >
                Resume setup
              </button>
              {running && (
                <button
                  className="ghost"
                  onClick={() => {
                    stop.current = true;
                  }}
                >
                  Stop after current step
                </button>
              )}
            </div>
          )}
          <small>
            Progress is saved after each step. If this page closes or sign-in
            expires, reconnect and resume here. Existing agents are preserved.
          </small>
        </>
      ) : (
        <form action={approve}>
          <input type="hidden" name="org" value={org} />
          <input type="hidden" name="version" value={version} />
          <fieldset
            disabled={pending || !connected || !templateReady}
            style={{
              border: 0,
              padding: 0,
              margin: 0,
              display: "grid",
              gap: 14,
              minWidth: 0,
            }}
          >
            <label>
              Phone number
              <select name="number" required defaultValue="">
                <option value="" disabled>
                  Select an available number
                </option>
                {available.map((n) => (
                  <option
                    key={`${n.connection_id}:${n.phone_number}`}
                    value={JSON.stringify({
                      connection_id: n.connection_id,
                      phone_number: n.phone_number,
                    })}
                  >
                    {n.phone_number} · {n.label}
                  </option>
                ))}
              </select>
            </label>
            {!available.length && (
              <p>
                No free numbers found. Add a number in Sarvam, then refresh this
                page.
              </p>
            )}
            <fieldset>
              <legend>Approve requested services</legend>
              {services.map((service) => (
                <label key={service} style={{ display: "block", padding: 8 }}>
                  <input
                    style={{ width: "auto", marginRight: 8 }}
                    type="checkbox"
                    name="approved_services"
                    value={service}
                    defaultChecked
                  />
                  {service}
                </label>
              ))}
            </fieldset>
            <p className="sub">
              Approval creates and publishes the agent and assigns this number
              for inbound calls. The client’s booking switch stays off until
              they choose spaces and enable it.
            </p>
            <div>
              <button disabled={!available.length}>
                {pending ? "Approving…" : "Approve and create agent"}
              </button>
            </div>
          </fieldset>
          {result.error && (
            <p role="alert" className="info-note">
              {result.error}
            </p>
          )}
        </form>
      )}
    </section>
  );
}
