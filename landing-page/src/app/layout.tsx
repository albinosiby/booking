import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: "BookingOS — bookings, teams and operations",
  description:
    "One operating system for managing venue bookings, teams, payments and everyday operations.",
  icons: {
    icon: "/_landing/images/bookingos-mark.png",
    apple: "/_landing/images/bookingos-mark.png",
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
