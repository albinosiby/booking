"use client";
import { useActionState } from "react";
import { signIn } from "../actions";

export default function Login() {
  const [error, action, pending] = useActionState(signIn, null);
  return (
    <div className="login">
      <form action={action}>
        <div>
          <h1>Booking Admin</h1>
          <p className="sub">Enter the admin password.</p>
        </div>
        <input name="password" type="password" placeholder="Password" autoComplete="current-password" autoFocus required />
        {error && <div className="err" role="alert">{error}</div>}
        <button disabled={pending}>{pending ? "Signing in…" : "Sign in"}</button>
      </form>
    </div>
  );
}
