import { z } from "zod";
import type SMTPTransport from "nodemailer/lib/smtp-transport";
import type Mail from "nodemailer/lib/mailer";

export interface TeamAccessNotice {
  email: string;
  name: string;
  organization: string;
  role: string;
  permissions: string[];
  assignments: Array<{ business: string; resources: string[] }>;
}
export interface TeamAccessMailer {
  send(notice: TeamAccessNotice): Promise<void>;
}
type MailTransport = {
  sendMail(
    message: Mail.Options,
  ): Promise<Pick<SMTPTransport.SentMessageInfo, "accepted" | "rejected">>;
  close(): void;
};
type SmtpFactory = (options: SMTPTransport.Options) => Promise<MailTransport>;
const smtpTransport: SmtpFactory = async (options) => {
  const { default: nodemailer } = await import("nodemailer");
  return nodemailer.createTransport(options);
};
const labels: Record<string, string> = {
  view_bookings: "View bookings",
  manage_bookings: "Create and edit bookings",
  collect_payments: "Record collections",
  mark_attendance: "Mark attendance",
  manage_attendance: "Mark attendance",
  manage_subscriptions: "Manage subscriptions",
  record_expenses: "Record expenses",
  view_finance: "View financial reports",
  coach: "Teach assigned coaching plans",
};
const escapeHtml = (text: string) =>
  text.replace(
    /[&<>"']/g,
    (char) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        char
      ]!,
  );

export function teamLoginUrls(env = process.env) {
  const web = new URL(
    env.TEAM_LOGIN_WEB_URL || "https://bookingos.online/app/sign-in",
  );
  if (
    (web.protocol !== "https:" &&
      !(
        env.NODE_ENV !== "production" &&
        web.protocol === "http:" &&
        ["localhost", "127.0.0.1"].includes(web.hostname)
      )) ||
    web.username ||
    web.password ||
    web.search ||
    web.hash ||
    !web.pathname.endsWith("/sign-in")
  )
    throw new Error("Invalid team web login URL");
  return {
    web: web.toString(),
    app: "bookingservice.tatos.tech://login/sign-in",
  };
}

export function teamAccessMessage(
  notice: TeamAccessNotice,
  urls = teamLoginUrls(),
) {
  const permissions = [
    ...new Set(notice.permissions.map((p) => labels[p]).filter(Boolean)),
  ];
  const scope = notice.assignments.map(
    (a) =>
      `${a.business}: ${a.resources.length ? a.resources.join(", ") : "All resources"}`,
  );
  const lines = [
    `Hello ${notice.name},`,
    "",
    `You have been added to ${notice.organization} on BookingOS.`,
    `Responsibility: ${notice.role === "manager" ? "Manager" : "Staff"}`,
    "",
    "Your business and resource access:",
    ...scope.map((line) => `• ${line}`),
    "",
    "Your permissions:",
    ...(permissions.length
      ? permissions.map((p) => `• ${p}`)
      : [
          "No operational permissions enabled. Contact your owner if you need access.",
        ]),
    "",
    `Sign in with Google using ${notice.email}. Your saved team access activates automatically and opens your dashboard.`,
    "You can also use a verified email/password account with this same email address.",
    "",
    `Web login: ${urls.web}`,
    `App login (installed BookingOS app): ${urls.app}`,
    "If the app link does not open, use Web login or open the installed app and choose Sign in.",
    "No invitation link, acceptance code or separate approval is required. Your owner can change or remove access.",
    "",
    "If you were not expecting this email, contact the organization owner. Signing in with another email will not grant this access.",
  ];
  const list = (items: string[]) =>
    `<ul>${items.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>`;
  return {
    subject: `Your BookingOS access to ${notice.organization.replace(/[\r\n]/g, " ")}`,
    text: lines.join("\n"),
    html: `<html><body style="font-family:Arial,sans-serif;color:#20251d;max-width:600px;margin:32px auto;padding:24px"><h1 style="font-size:24px">Welcome to ${escapeHtml(notice.organization)}</h1><p>Hello ${escapeHtml(notice.name)}, you have been added to BookingOS as ${notice.role === "manager" ? "Manager" : "Staff"}.</p><h2 style="font-size:18px">Your access</h2>${list(scope)}<h2 style="font-size:18px">Your permissions</h2>${permissions.length ? list(permissions) : "<p>No operational permissions enabled. Contact your owner if you need access.</p>"}<p>Sign in with Google using <strong>${escapeHtml(notice.email)}</strong>. Your team access activates automatically and opens your dashboard. A verified email/password account with the same email also works.</p><p><a href="${escapeHtml(urls.web)}" style="display:inline-block;background:#b2f35b;color:#16210a;padding:14px 24px;border-radius:10px;text-decoration:none">Sign in on the web</a></p><p><a href="${escapeHtml(urls.app)}">Open the BookingOS app</a> (requires the installed app)</p><p>If the app link does not open, use Web login or open the installed app and choose Sign in. No invitation link or acceptance code is required.</p><p>Your owner can change or remove access. If you were not expecting this email, contact the organization owner. Another email will not grant this access.</p></body></html>`,
  };
}

/** Credentials stay in server secrets. Never log transport errors or messages. */
export class NodemailerTeamAccessMailer implements TeamAccessMailer {
  constructor(
    private readonly factory: SmtpFactory = smtpTransport,
    private readonly environment = process.env,
  ) {}
  async send(notice: TeamAccessNotice) {
    const env = this.environment;
    const config = z
      .object({
        SMTP_HOST: z.string().min(1),
        SMTP_PORT: z.coerce.number().int().min(1).max(65535).default(465),
        SMTP_USER: z.string().min(1),
        SMTP_PASSWORD: z.string().min(1),
        SMTP_FROM: z.email(),
      })
      .parse(env);
    const message = teamAccessMessage(notice, teamLoginUrls(env));
    const transport = await this.factory({
      host: config.SMTP_HOST,
      port: config.SMTP_PORT,
      secure: config.SMTP_PORT === 465,
      requireTLS: config.SMTP_PORT !== 465,
      auth: { user: config.SMTP_USER, pass: config.SMTP_PASSWORD },
      tls: { rejectUnauthorized: true },
      connectionTimeout: 8000,
      greetingTimeout: 8000,
      socketTimeout: 12000,
      disableFileAccess: true,
      disableUrlAccess: true,
      logger: false,
      debug: false,
    });
    let deadline: ReturnType<typeof setTimeout> | undefined;
    try {
      const info = await Promise.race([
        transport.sendMail({
          from: { name: "BookingOS", address: config.SMTP_FROM },
          to: { name: notice.name, address: notice.email },
          ...message,
        }),
        new Promise<never>((_, reject) => {
          deadline = setTimeout(
            () => reject(new Error("Email delivery timed out")),
            15000,
          );
        }),
      ]);
      if (!info.accepted?.length || info.rejected?.length)
        throw new Error("Email was not accepted");
    } finally {
      clearTimeout(deadline);
      transport.close();
    }
  }
}
