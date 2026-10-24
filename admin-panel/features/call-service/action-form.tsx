"use client";
import { useActionState, type ReactNode } from "react";
import type { ActionResult } from "./actions";
export function ActionForm({
  action,
  children,
  className = "card",
  id,
}: {
  action: (previous: ActionResult, form: FormData) => Promise<ActionResult>;
  children: ReactNode;
  className?: string;
  id?: string;
}) {
  const [state, submit, pending] = useActionState(action, {});
  return (
    <form
      id={id}
      action={submit}
      className={className}
      style={{ display: "grid", gap: 14 }}
      aria-busy={pending}
    >
      <fieldset
        disabled={pending}
        style={{
          border: 0,
          padding: 0,
          margin: 0,
          minWidth: 0,
          display: "grid",
          gap: 14,
        }}
      >
        {children}
      </fieldset>
      {pending && <p role="status">Saving…</p>}
      {state.error && (
        <p role="alert" className="info-note">
          {state.error}
        </p>
      )}
      {state.success && <p role="status">{state.success}</p>}
      {state.key && (
        <div className="msg">
          <p>
            Copy this key now into the provider’s secure secret field. It is
            shown once. Previous keys no longer work.
          </p>
          <code style={{ overflowWrap: "anywhere" }}>{state.key}</code>
        </div>
      )}
    </form>
  );
}
