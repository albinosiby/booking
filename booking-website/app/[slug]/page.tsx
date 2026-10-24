import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { OrganisationHome } from "../../components/organisation-home";
import { headers } from "next/headers";
import { loadWebsite } from "../../lib/server-api";
import { siteBasePath } from "../../lib/site-links";
import { SITE_HOST_HEADER } from "../../lib/site-host";
import { siteIcons } from "../../lib/site-icons";
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
        icons: siteIcons(site, preview),
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
  const site = await loadWebsite(slug, preview);
  if (!site) notFound();
  return (
    <OrganisationHome
      base={siteBasePath(slug, (await headers()).get(SITE_HOST_HEADER))}
      preview={preview}
      site={site}
    />
  );
}
