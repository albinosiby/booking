"use client";
import { useActionState, useState } from "react";
import { signIn } from "../actions";
import { Brand, Icon } from "../../components/icon";

export default function Login() {
  const [error, action, pending] = useActionState(signIn, null);
  const [visible, setVisible] = useState(false);
  return (
    <div className="login-layout">
      <section className="login-main">
        <Brand />
        <div className="login-form-wrap">
          <span className="login-lock">
            <Icon name="lock" size={25} />
          </span>
          <p className="eyebrow">WELCOME BACK</p>
          <h1>Your workspace awaits.</h1>
          <p className="sub">
            Sign in to manage your platform, people, and everything in between.
          </p>
          <form action={action}>
            <label htmlFor="admin-password">Admin password</label>
            <div className="password-field">
              <input
                id="admin-password"
                name="password"
                type={visible ? "text" : "password"}
                placeholder="Enter your password"
                autoComplete="current-password"
                autoFocus
                required
                aria-describedby={error ? "login-error" : undefined}
                aria-invalid={!!error}
              />
              <button
                type="button"
                className="password-toggle"
                aria-label={visible ? "Hide password" : "Show password"}
                aria-pressed={visible}
                onClick={() => setVisible(!visible)}
              >
                <Icon name={visible ? "eyeOff" : "eye"} size={19} />
              </button>
            </div>
            {error && (
              <div id="login-error" className="form-error" role="alert">
                {error}
              </div>
            )}
            <button className="login-submit" disabled={pending}>
              {pending ? "Signing in…" : "Sign in to workspace"}
              <Icon name="arrow" size={18} />
            </button>
          </form>
          <p className="login-help">
            <Icon name="lock" size={13} /> Access for platform administrators
          </p>
        </div>
        <p className="login-footer">
          BookingOS <span>·</span> A little more organized.
        </p>
      </section>
      <aside className="login-showcase">
        <span className="showcase-caption">
          <span /> YOUR PLATFORM. CONNECTED.
        </span>
        <div className="showcase-art" aria-hidden="true">
          <div className="showcase-window">
            <div className="showcase-window-top">
              <i />
              <i />
              <i />
              <span />
            </div>
            <div className="showcase-window-content">
              <div className="showcase-mini-nav">
                <b />
                <i />
                <i />
                <i />
                <i />
              </div>
              <div className="showcase-mini-main">
                <span className="mini-line" />
                <div className="mini-cards">
                  <i />
                  <i />
                  <i />
                </div>
                <div className="mini-table">
                  <span />
                  <span />
                  <span />
                  <span />
                </div>
              </div>
            </div>
          </div>
          <div className="showcase-float">
            <span>
              <Icon name="check" size={17} />
            </span>
            Everything in one place.
          </div>
        </div>
        <h2>
          One space.
          <br />A clearer perspective.
        </h2>
        <p>
          From the first booking to the next big milestone. Keep your people and
          operations moving together.
        </p>
        <div className="showcase-tags">
          <span>
            <Icon name="organizations" size={15} /> Organizations
          </span>
          <span>
            <Icon name="support" size={15} /> Support
          </span>
          <span>
            <Icon name="phone" size={15} /> Agent calls
          </span>
        </div>
        <div className="showcase-bottom">
          BUILT FOR THE WAY YOU WORK <span>↗</span>
        </div>
      </aside>
    </div>
  );
}
