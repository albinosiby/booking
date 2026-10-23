import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: "BookingOS — bookings, teams and operations",
  description:
    "One operating system for managing venue bookings, teams, payments and everyday operations.",
  icons: {
    icon: [
      {
        url: "/_landing/images/bookingos-app-icon.png",
        type: "image/png",
        sizes: "192x192",
      },
    ],
    apple: "/_landing/images/bookingos-app-icon.png",
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
