"use client";
import { useActionState } from "react";
import { generateToolKey } from "../app/actions";

export function ToolKey({ org, has }: { org: string; has: boolean }) {
  const [key, action, pending] = useActionState(generateToolKey, null);
  return (
    <form action={action} style={{ display: "grid", gap: 10 }}>
      <input type="hidden" name="org" value={org} />
      {key && (
        <div className="msg">
          <small>
            Copy this now. It is shown once and replaces any earlier key.
          </small>
          <p>
            <code>{key}</code>
          </p>
        </div>
      )}
      <div>
        <button className="ghost" disabled={pending}>
          {pending
            ? "Generating…"
            : has
              ? "Generate a new tool key"
              : "Generate tool key"}
        </button>
      </div>
    </form>
  );
}
