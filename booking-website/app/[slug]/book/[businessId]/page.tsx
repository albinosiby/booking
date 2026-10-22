import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { BookingPage } from "../../../../components/booking-page";
import { loadWebsite } from "../../../../lib/server-api";
export const dynamic = "force-dynamic";
type Props = {
  params: Promise<{ slug: string; businessId: string }>;
  searchParams: Promise<{ preview?: string }>;
};
export async function generateMetadata({
  params,
  searchParams,
}: Props): Promise<Metadata> {
  const { slug, businessId } = await params,
    { preview } = await searchParams;
  const site = await loadWebsite(slug, preview),
    business = site?.businesses.find((b) => b.id === businessId);
  return {
    title:
      business && site
        ? `${business.name} | ${site.title}`
        : "Space unavailable",
    robots: {
      index: !!site && !site.is_preview && site.status === "published",
      follow: !site?.is_preview,
    },
  };
}
export default async function ServiceBookingPage({
  params,
  searchParams,
}: Props) {
  const { slug, businessId } = await params,
    { preview } = await searchParams;
  const site = await loadWebsite(slug, preview),
    business = site?.businesses.find((b) => b.id === businessId);
  if (!site || !business) notFound();
  return (
    <BookingPage
      slug={slug}
      preview={preview}
      initialSite={{ ...site, businesses: [business] }}
    />
  );
}
