import type { Metadata } from "next";
import { adminPath } from "../lib/paths";
import "./globals.css";
export const metadata: Metadata = {
  title: "BookingOS · Admin",
  description: "Your platform, people, and operations in one workspace.",
  robots: { index: false, follow: false },
  icons: {
    icon: {
      url: adminPath("/booking-os-logo.png?v=20261030"),
      type: "image/png",
      sizes: "192x192",
    },
    apple: adminPath("/booking-os-logo.png?v=20261030"),
  },
};
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
