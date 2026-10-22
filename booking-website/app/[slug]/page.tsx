import type { Metadata } from "next";
import { OrganisationHome } from "../../components/organisation-home";
import { loadWebsite } from "../../lib/server-api";
export const dynamic = "force-dynamic";
type Props = {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ preview?: string }>;
};
export async function generateMetadata({
  params,
  searchParams,
}: Props): Promise<Metadata> {
  const { slug } = await params,
    { preview } = await searchParams;
  const site = await loadWebsite(slug, preview);
  return site
    ? {
        title: `${site.title} | Book online`,
        description:
          site.description || `Book an available space at ${site.title}.`,
        robots: {
          index: !site.is_preview && site.status === "published",
          follow: !site.is_preview,
        },
        openGraph: {
          title: site.title,
          description: site.description,
          type: "website",
        },
      }
    : { title: "Booking website", robots: { index: false, follow: false } };
}
export default async function SitePage({ params, searchParams }: Props) {
  const { slug } = await params,
    { preview } = await searchParams;
  return (
    <OrganisationHome
      preview={preview}
      site={await loadWebsite(slug, preview)}
    />
  );
}
