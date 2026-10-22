import type { ComponentPropsWithoutRef } from "react";
import { Button as ShadButton } from "./button";
import { Card as ShadCard } from "./card";
import { cn } from "@/lib/utils";

export function Card({
  className,
  children,
  padded = true,
  ...rest
}: ComponentPropsWithoutRef<"div"> & { padded?: boolean }) {
  return (
    <ShadCard
      {...rest}
      className={cn(
        "border-line/80 bg-surface-raised shadow-card transition-shadow duration-200",
        padded && "p-6",
        className
      )}
    >
      {children}
    </ShadCard>
  );
}

type ButtonVariant = "primary" | "secondary" | "ghost" | "danger" | "whatsapp" | "outlineBrand";
type ButtonSize = "sm" | "md" | "lg";

const buttonVariants: Record<ButtonVariant, string> = {
  primary: "btn-premium bg-brand text-white",
  secondary: "border border-line bg-surface-raised text-ink hover:border-line-strong hover:bg-surface-sunken",
  outlineBrand: "border-brand bg-surface-raised text-brand hover:bg-brand-wash/40 hover:text-brand",
  ghost: "text-ink-secondary hover:bg-surface-sunken hover:text-ink",
  danger: "",
  whatsapp: "",
};

const buttonSizes: Record<ButtonSize, string> = {
  sm: "h-8 px-3 text-[12px]",
  md: "h-10 px-4 text-[14px]",
  lg: "h-12 px-6 text-[14px]",
};

export function Button({
  variant = "primary",
  size = "md",
  className,
  type = "button",
  ...rest
}: ComponentPropsWithoutRef<"button"> & { variant?: ButtonVariant; size?: ButtonSize; asChild?: boolean }) {
  const shadVariant = variant === "danger" ? "destructive" : variant === "ghost" ? "ghost" : variant === "whatsapp" ? "whatsapp" : variant === "primary" ? "default" : variant === "outlineBrand" ? "outline" : "secondary";
  const shadSize = size === "lg" ? "lg" : size === "sm" ? "sm" : "default";
  return (
    <ShadButton
      type={type}
      variant={shadVariant}
      size={shadSize}
      {...rest}
      className={cn("font-semibold transition-all duration-150 active:scale-[0.98]", buttonVariants[variant], buttonSizes[size], className)}
    />
  );
}

