"use client";

import { useEffect, useTransition } from "react";
import { usePathname, useRouter } from "next/navigation";

export function RefreshData() {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = useTransition();
  useEffect(() => {
    const path = pathname.replace(/^\/admin(?=\/|$)/, "") || "/";
    if (!["/", "/organizations", "/users", "/audit"].includes(path)) return;
    const refresh = () => {
      if (document.visibilityState === "visible" && !pending && !document.activeElement?.closest("form")) {
        startTransition(() => router.refresh());
      }
    };
    const timer = window.setInterval(refresh, 30000);
    document.addEventListener("visibilitychange", refresh);
    window.addEventListener("online", refresh);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", refresh);
      window.removeEventListener("online", refresh);
    };
  }, [pathname, router, pending]);
  return (
    <button
      type="button"
      disabled={pending}
      aria-busy={pending}
      onClick={() => startTransition(() => router.refresh())}
    >
      {pending ? "Refreshing…" : "Refresh data"}
    </button>
  );
}
