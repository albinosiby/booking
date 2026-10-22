import { clsx } from "clsx";
import Image from "next/image";

export const BOOKOS_MARK = "/_landing/images/bookingos-mark.png";

const sizes = { sm: 28, md: 36, lg: 44 } as const;

/** Product mark + optional wordmark. Use this instead of a letter-B placeholder. */
export function BookosLogo({
  href,
  wordmark = true,
  size = "md",
  className,
  wordmarkClassName,
  subtitle,
}: {
  href?: string;
  wordmark?: boolean;
  size?: keyof typeof sizes;
  className?: string;
  wordmarkClassName?: string;
  subtitle?: string;
}) {
  const px = sizes[size];
  const mark = (
    <span className={clsx("inline-flex items-center gap-2.5", className)}>
      <Image
        src={BOOKOS_MARK}
        alt={wordmark ? "" : "BookingOS"}
        width={px}
        height={px}
        className="shrink-0 rounded-[10px]"
        priority
      />
      {wordmark ? (
        <span className="flex min-w-0 flex-col leading-tight">
          <span className={clsx("font-display font-bold", wordmarkClassName ?? "text-[16px] text-brand")}>BookingOS</span>
          {subtitle ? <span className="t-small text-ink-secondary">{subtitle}</span> : null}
        </span>
      ) : null}
    </span>
  );
  if (!href) return mark;
  return (
    <a href={href} className="inline-flex items-center" aria-label="BookingOS">
      {mark}
    </a>
  );
}

export function BookosMark({ size = 16, className }: { size?: number; className?: string }) {
  return (
    <Image
      src={BOOKOS_MARK}
      alt="BookingOS"
      width={size}
      height={size}
      className={clsx("inline-block rounded-[4px]", className)}
    />
  );
}
