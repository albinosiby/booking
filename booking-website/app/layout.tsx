import type { Metadata } from "next";
import { siteIcons } from "../lib/site-icons";
import "./globals.css";
export const metadata: Metadata = {
  title: "Book your space | Booking OS",
  description:
    "Choose your space, find an available time and book directly with the venue.",
  robots: { index: false, follow: false },
  icons: siteIcons(null),
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
