import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {
  title: "BookingOS · Admin",
  description: "Your platform, people, and operations in one workspace.",
  robots: { index: false, follow: false },
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
