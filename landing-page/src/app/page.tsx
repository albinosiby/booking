import {
  ArrowRight,
  BedDouble,
  CalendarDays,
  ChevronDown,
  CirclePlay,
  CreditCard,
  Dumbbell,
  GraduationCap,
  Heart,
  LayoutDashboard,
  Menu,
  MessageSquare,
  PartyPopper,
  Search,
  Scissors,
  ShieldCheck,
  Smartphone,
  Users,
  Waves,
} from "lucide-react";
import type { ReactNode } from "react";
import { Button, Card } from "@/components/ui/primitives";
import { BookosLogo, BookosMark } from "@/components/brand/BookosLogo";

export const metadata = {
  title: "BookingOS — bookings, teams and operations",
  description:
    "One operating system for managing venue bookings, teams, payments and everyday operations.",
};

const verticals = [
  { label: "Turf", icon: Dumbbell },
  { label: "Court", icon: Dumbbell },
  { label: "Pool", icon: Waves },
  { label: "Rooms", icon: BedDouble },
  { label: "Hall", icon: PartyPopper },
  { label: "Salon", icon: Scissors },
  { label: "Clinic", icon: Heart },
  { label: "Coaching", icon: GraduationCap },
];

const journey = [
  {
    step: "01",
    title: "Set up spaces",
    detail: "Add your assets, slot rules, and booking options in one place.",
  },
  {
    step: "02",
    title: "Assign roles",
    detail: "Give staff clear rights: management, cleaning, or task-only access.",
  },
  {
    step: "03",
    title: "Collect bookings",
    detail: "Customers pick their slot and pay using your configured flow.",
  },
  {
    step: "04",
    title: "Confirm + remind",
    detail: "Automations reduce no-shows and remove repetitive manual WhatsApp work.",
  },
  {
    step: "05",
    title: "Monitor outcomes",
    detail: "Use dashboard insights to tune hours, pricing, and team routines.",
  },
];

const features = [
  {
    icon: LayoutDashboard,
    title: "Adaptive dashboard",
    body: "Monitor every asset from one command screen built for bookings, payments, and operational tasks.",
  },
  {
    icon: MessageSquare,
    title: "WhatsApp-first automation",
    body: "Send confirmations and updates that keep your customers informed without delay.",
  },
  {
    icon: Smartphone,
    title: "Staff app",
    body: "Team tasks and role-based management move from web to phone with minimal handoff loss.",
  },
  {
    icon: ShieldCheck,
    title: "Audit-safe operations",
    body: "Track payment proofs, booking changes, and task completion history in one place.",
  },
];

export default function LandingPage() {
  return (
    <main className="min-h-screen bg-[#06111d]">
      <section className="relative isolate min-h-[820px] overflow-hidden bg-[#06111d] text-white lg:min-h-screen">
        <video
          autoPlay
          preload="metadata"
          muted
          loop
          playsInline
          poster="/_landing/images/bookingos-turf-hero-v2.png"
          className="absolute inset-0 -z-20 h-full w-full object-cover object-center"
          aria-label="Football player dribbling on a turf"
        >
          <source src="/_landing/videos/bookingos-turf-dribble.mp4" type="video/mp4" />
        </video>
        <div className="absolute inset-0 -z-10 bg-[linear-gradient(90deg,rgba(2,10,18,.92)_0%,rgba(3,12,20,.72)_35%,rgba(3,12,20,.24)_69%,rgba(2,10,18,.53)_100%)]" />
        <div className="absolute inset-0 -z-10 bg-[linear-gradient(0deg,rgba(2,10,17,.92)_0%,transparent_39%,rgba(2,10,17,.38)_100%)]" />
        <div className="pointer-events-none absolute -left-32 top-24 -z-10 h-[31rem] w-[29rem] rounded-full bg-cyan-500/10 blur-[125px]" />

        <header className="relative z-30 mx-auto flex h-[78px] max-w-[1480px] items-center gap-8 px-5 lg:h-[98px] lg:px-10">
          <BookosLogo href="/" size="sm" wordmarkClassName="text-[26px] text-white" />
          <nav className="ml-12 hidden items-center gap-9 lg:flex">
            <a href="#visuals" className="text-[15px] font-medium text-white/84 transition hover:text-white">Product preview</a>
            {[
              "Features",
              "Industries",
            ].map((item) => (
              <a key={item} href={`#${item.toLowerCase()}`} className="text-[15px] font-medium text-white/84 transition hover:text-white">
                {item}
              </a>
            ))}
            <a href="#resources" className="flex items-center gap-1 text-[15px] font-medium text-white/84 transition hover:text-white">
              Resources <ChevronDown size={15} />
            </a>
          </nav>
          <div className="ml-auto hidden items-center gap-7 sm:flex">
            <a href="/app/sign-in" className="text-[15px] font-medium text-white/85 transition hover:text-white">Sign in</a>
            <a href="/app/register" className="group inline-flex items-center gap-2 rounded-full bg-white px-5 py-3 text-[14px] font-bold text-slate-950 shadow-[0_12px_40px_rgba(0,0,0,.2)] transition hover:-translate-y-0.5 hover:bg-cyan-50">
              Start free <ArrowRight size={17} className="transition-transform group-hover:translate-x-0.5" />
            </a>
          </div>
          <details className="group relative ml-auto lg:hidden">
            <summary className="flex size-10 cursor-pointer list-none items-center justify-center rounded-full border border-white/20 bg-black/15 text-white marker:hidden" aria-label="Open navigation">
              <Menu size={20} />
            </summary>
            <div className="absolute right-0 top-12 w-48 rounded-[14px] border border-white/15 bg-[#07121e]/95 p-2 shadow-2xl backdrop-blur-xl">
              <a href="#visuals" className="block rounded-[8px] px-3 py-2 text-sm text-white/80 hover:bg-white/10 hover:text-white">Product preview</a>
              {["Features", "Industries", "Resources"].map((item) => (
                <a key={item} href={`#${item.toLowerCase()}`} className="block rounded-[8px] px-3 py-2 text-sm text-white/80 hover:bg-white/10 hover:text-white">{item}</a>
              ))}
              <a href="/app/register" className="mt-1 block rounded-[8px] bg-white px-3 py-2 text-sm font-semibold text-slate-950">Start free</a>
            </div>
          </details>
        </header>

        <div className="relative mx-auto grid max-w-[1480px] gap-4 px-5 pb-8 pt-8 md:grid-cols-[.92fr_1.08fr] md:px-8 md:pb-20 md:pt-14 lg:grid-cols-[.87fr_1.13fr] lg:px-10 lg:pb-44 lg:pt-20">
          <div className="relative z-10 md:pt-6 lg:pt-8">
            <p className="hero-enter inline-flex items-center gap-2 rounded-full border border-white/15 bg-[#07121e]/55 px-3.5 py-2 text-[10px] font-semibold tracking-[.15em] text-white/75 backdrop-blur-sm" style={{ animationDelay: "80ms" }}>
              <span className="size-2 rounded-full bg-emerald-300 shadow-[0_0_12px_#6ee7b7]" />
              BUILT FOR MODERN OPERATORS
            </p>
            <h1 className="hero-enter mt-5 max-w-[620px] font-display text-[48px] font-bold leading-[.98] tracking-[-2px] text-white sm:text-[72px] lg:mt-6 lg:text-[84px]" style={{ animationDelay: "150ms" }}>
              Run your<br />bookings.<br />
              <span className="bg-gradient-to-r from-cyan-300 via-sky-400 to-teal-200 bg-clip-text text-transparent">Not the chaos.</span>
            </h1>
            <p className="hero-enter mt-6 max-w-[530px] text-[17px] leading-8 text-white/74 sm:text-[19px]" style={{ animationDelay: "230ms" }}>
              One calm operating system for bookings, teams, payments, and every detail in between.
            </p>
            <div className="hero-enter mt-7 flex gap-3 sm:flex-wrap" style={{ animationDelay: "310ms" }}>
              <a href="/app/register" className="group inline-flex flex-1 items-center justify-center gap-2 rounded-full bg-white px-5 py-3.5 text-[14px] font-bold text-slate-950 shadow-[0_14px_45px_rgba(0,0,0,.28)] transition hover:-translate-y-0.5 hover:bg-cyan-50 sm:flex-none sm:px-6 sm:py-4 sm:text-[15px]">
                Start free <ArrowRight size={18} className="transition-transform group-hover:translate-x-1" />
              </a>
              <a href="#journey" className="inline-flex flex-1 items-center justify-center gap-2 rounded-full border border-white/25 bg-black/15 px-4 py-3.5 text-[14px] font-semibold text-white backdrop-blur-sm transition hover:border-white/50 hover:bg-white/10 sm:flex-none sm:px-6 sm:py-4 sm:text-[15px]">
                <CirclePlay size={19} /> Watch demo
              </a>
            </div>
          </div>

          <ProductShowcase />
        </div>

        <div className="relative z-10 mx-5 mt-3 max-w-[1480px] border-t border-white/15 px-0 py-6 lg:absolute lg:inset-x-10 lg:bottom-0 lg:mx-auto lg:mt-0 lg:py-7">
          <div className="grid grid-cols-2 gap-x-3 gap-y-5 sm:gap-5 lg:grid-cols-4">
            {[
              [CalendarDays, "Manage bookings", "in minutes"],
              [Users, "Organize your team", "with ease"],
              [CreditCard, "Accept payments", "online & on-site"],
              [LayoutDashboard, "Grow your business", "with real-time insights"],
            ].map(([Icon, title, body], index) => {
              const FeatureIcon = Icon as typeof CalendarDays;
              return (
                <div key={String(title)} className={`flex items-center gap-3 ${index > 0 ? "lg:border-l lg:border-white/15 lg:pl-6" : ""}`}>
                  <FeatureIcon size={22} className="shrink-0 text-cyan-300 sm:size-[25px]" />
                  <p className="text-[11px] leading-4 text-white/65 sm:text-[13px] sm:leading-5"><strong className="block font-semibold text-white">{String(title)}</strong>{String(body)}</p>
                </div>
              );
            })}
          </div>
        </div>

        <div className="absolute bottom-24 right-7 z-10 hidden items-center gap-3 text-[12px] text-white/45 xl:flex">
          <div className="flex h-28 flex-col items-center justify-between border-l border-white/30 pl-4"><b className="text-white">01</b><span>02</span><span>03</span></div>
          <a href="#journey" className="flex size-14 items-center justify-center rounded-full border border-white/30 text-white transition hover:bg-white/10" aria-label="Scroll to the next section"><ArrowRight size={20} className="rotate-90" /></a>
        </div>
      </section>

      <section id="industries" className="relative isolate scroll-mt-16 overflow-hidden border-t border-[#143047] bg-[#071827] py-20 text-white">
        <div className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(circle_at_82%_3%,rgba(22,149,178,.27),transparent_29%),radial-gradient(circle_at_11%_100%,rgba(14,71,107,.25),transparent_38%)]" />
        <div className="mx-auto max-w-[1180px] px-6">
          <div className="grid gap-10 lg:grid-cols-[.8fr_1.2fr] lg:items-end">
            <div>
              <p className="font-semibold uppercase tracking-[0.16em] text-cyan-300/85">Built for venues</p>
              <h2 className="mt-3 max-w-[480px] text-[44px] font-display font-bold leading-[1.04] text-white">Every space. One calm operating system.</h2>
              <p className="mt-5 max-w-[440px] text-[16px] leading-7 text-white/65">
                A consistent booking flow for the spaces your business runs today, and the next one you add tomorrow.
              </p>
              <p className="mt-7 border-l-2 border-cyan-300 pl-3 text-[13px] font-medium text-cyan-100/80">One brand experience, even when your operations become more complex.</p>
            </div>
            <div className="border-l border-white/15 pl-6 lg:pl-10">
              <p className="text-[11px] font-semibold uppercase tracking-[.15em] text-white/45">A system that adapts to</p>
              <div className="mt-5 grid grid-cols-2 gap-x-8 gap-y-4 sm:grid-cols-4 lg:grid-cols-2">
                {verticals.map((v) => {
                  const Icon = v.icon;
                  return (
                    <div key={v.label} className="group flex items-center gap-3 text-white/65 transition hover:text-white">
                      <span className="flex size-9 items-center justify-center rounded-full border border-white/10 bg-white/[.04] transition group-hover:border-cyan-300/55 group-hover:bg-cyan-300/10">
                        <Icon size={17} className="text-cyan-300" />
                      </span>
                      <span className="text-[15px] font-medium">{v.label}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>

          <div className="relative mt-14 overflow-hidden rounded-[16px] border border-cyan-200/15 bg-[radial-gradient(circle_at_80%_0%,rgba(34,211,238,.24),transparent_31%),linear-gradient(120deg,#0c2a3c,#06131e_60%)] p-5 shadow-[0_24px_70px_rgba(0,0,0,.28)] sm:p-8">
            <div className="pointer-events-none absolute -right-12 top-0 h-48 w-64 rounded-full bg-cyan-400/15 blur-[90px]" />
            <div className="relative grid gap-8 lg:grid-cols-[.78fr_1.22fr] lg:items-center">
              <div>
                <div className="inline-flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[.15em] text-cyan-200/80"><span className="size-2 rounded-full bg-emerald-300 shadow-[0_0_10px_#6ee7b7]" /> Live operations</div>
                <h3 className="mt-4 text-[27px] font-display font-bold text-white">One view for the moving parts.</h3>
                <p className="mt-3 max-w-[370px] text-[15px] leading-7 text-white/58">Bookings, check-ins, staff handoffs, and payments stay clear even when the venue gets busy.</p>
                <div className="mt-6 flex flex-wrap gap-2 text-[12px] text-white/65"><span className="rounded-full border border-white/10 bg-black/15 px-3 py-1.5">Role-based access</span><span className="rounded-full border border-white/10 bg-black/15 px-3 py-1.5">Live payment state</span></div>
              </div>
              <div className="overflow-hidden rounded-[11px] border border-white/10 bg-[#06111d]/90">
                <div className="flex items-center justify-between border-b border-white/10 px-4 py-3 text-[12px]"><span className="font-semibold text-white/80">Today&apos;s venue activity</span><span className="text-cyan-300">Live</span></div>
                <div className="p-4">
                  {[['06:00 PM', '5v5 Turf booking', 'Confirmed', 'bg-emerald-300'], ['07:30 PM', 'Court B · Team practice', 'Checked in', 'bg-cyan-300'], ['08:30 PM', 'Main turf · Corporate match', 'Payment pending', 'bg-amber-300']].map(([time, event, status, dot]) => (
                    <div key={time} className="grid grid-cols-[64px_1fr_auto] items-center gap-3 border-b border-white/[.07] py-3 last:border-0">
                      <span className="text-[11px] font-medium text-white/45">{time}</span>
                      <span className="text-[13px] font-medium text-white/85">{event}</span>
                      <span className="flex items-center gap-1.5 text-[10px] text-white/55"><i className={`size-1.5 rounded-full ${dot}`} />{status}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="features" className="scroll-mt-16 border-t border-slate-200 bg-[#f5f8fb] py-20 text-slate-950">
        <div className="mx-auto max-w-[1180px] px-6">
          <div className="grid gap-12 lg:grid-cols-[.9fr_1.1fr] lg:items-start">
            <div>
              <p className="font-semibold uppercase tracking-[0.16em] text-cyan-700">Capabilities</p>
              <h2 className="mt-3 max-w-[480px] text-[42px] font-display font-bold leading-[1.04] text-slate-950">Built for the real work behind every booking.</h2>
              <p className="mt-5 max-w-[440px] text-[16px] leading-7 text-slate-600">BookingOS keeps the customer experience simple because the operations behind it are clear, connected, and accountable.</p>
              <div className="mt-10 border-t border-slate-200">
                {features.map((feature, index) => {
                  const Icon = feature.icon;
                  return (
                    <div key={feature.title} className="group grid grid-cols-[34px_1fr_auto] gap-4 border-b border-slate-200 py-5">
                      <span className="pt-0.5 text-[11px] font-semibold text-cyan-700">0{index + 1}</span>
                      <div><h3 className="font-semibold text-slate-950">{feature.title}</h3><p className="mt-1 max-w-[350px] text-[14px] leading-6 text-slate-600">{feature.body}</p></div>
                      <span className="mt-1 flex size-9 items-center justify-center rounded-full border border-slate-200 bg-white text-cyan-700 transition group-hover:border-cyan-400 group-hover:bg-cyan-50"><Icon size={17} /></span>
                    </div>
                  );
                })}
              </div>
            </div>

            <div className="relative overflow-hidden rounded-[14px] border border-white/10 bg-[radial-gradient(circle_at_77%_13%,rgba(34,211,238,.18),transparent_33%),linear-gradient(135deg,#0d2637,#06111d)] p-5 sm:p-7">
              <div className="pointer-events-none absolute -right-16 top-12 h-52 w-52 rounded-full bg-cyan-300/10 blur-[80px]" />
              <div className="relative flex items-center justify-between border-b border-white/10 pb-4"><div><p className="text-[11px] font-semibold uppercase tracking-[.15em] text-white/45">The BookingOS control room</p><p className="mt-1 text-[18px] font-semibold text-white">Every signal in context.</p></div><span className="flex items-center gap-2 text-[11px] text-cyan-200"><i className="size-2 rounded-full bg-emerald-300 shadow-[0_0_10px_#6ee7b7]" /> Live</span></div>
              <div className="relative mt-7 grid grid-cols-[82px_1fr] gap-x-4 gap-y-5 text-[12px]">
                <span className="text-white/42">06:00 PM</span><div className="relative pt-1"><span className="absolute -left-2 top-0 size-3 rounded-full border-[3px] border-[#0a1c2a] bg-cyan-300" /><div className="h-2.5 w-[76%] rounded-full bg-cyan-400/85" /><p className="mt-2 text-white/75">Turf booking · confirmed</p></div>
                <span className="text-white/42">07:30 PM</span><div className="relative pt-1"><span className="absolute -left-2 top-0 size-3 rounded-full border-[3px] border-[#0a1c2a] bg-sky-300" /><div className="h-2.5 w-[52%] rounded-full bg-sky-300/80" /><p className="mt-2 text-white/75">Team check-in · completed</p></div>
                <span className="text-white/42">08:30 PM</span><div className="relative pt-1"><span className="absolute -left-2 top-0 size-3 rounded-full border-[3px] border-[#0a1c2a] bg-amber-300" /><div className="h-2.5 w-[88%] rounded-full bg-amber-300/80" /><p className="mt-2 text-white/75">Payment proof · awaiting review</p></div>
              </div>
              <div className="relative mt-8 grid grid-cols-3 gap-3 border-t border-white/10 pt-5"><div><p className="text-[11px] text-white/45">Open slots</p><p className="mt-1 text-[22px] font-bold text-white">18</p></div><div><p className="text-[11px] text-white/45">Check-ins</p><p className="mt-1 text-[22px] font-bold text-white">94%</p></div><div><p className="text-[11px] text-white/45">Team tasks</p><p className="mt-1 text-[22px] font-bold text-white">06</p></div></div>
            </div>
          </div>
        </div>
      </section>

      <section id="journey" className="scroll-mt-16 border-t border-slate-200 bg-[#f5f8fb] py-20 text-slate-950">
        <div className="mx-auto max-w-[1120px] px-6">
          <div className="grid gap-6 border-b border-slate-200 pb-10 md:grid-cols-[1fr_auto] md:items-end">
            <div className="max-w-[620px]">
              <p className="font-semibold uppercase tracking-[0.16em] text-cyan-700">Workflow script</p>
              <h2 className="mt-3 text-[40px] font-display font-bold leading-[1.06] text-slate-950">From setup to a smoother day.</h2>
              <p className="mt-4 text-[16px] leading-7 text-slate-600">A clear operating rhythm that turns a new space into a reliable booking experience.</p>
            </div>
            <div className="inline-flex items-center gap-2 self-start rounded-full border border-slate-200 bg-white px-4 py-2 text-[12px] font-semibold text-slate-600 md:self-auto"><span className="size-2 rounded-full bg-cyan-500" /> Five connected moments</div>
          </div>
          <div className="relative mt-10 grid gap-0 md:grid-cols-5">
            <div aria-hidden className="pointer-events-none absolute left-[8%] right-[8%] top-[27px] hidden h-px bg-gradient-to-r from-cyan-500 via-sky-300 to-slate-300 md:block" />
            {journey.map((item, index) => (
              <article key={item.step} className="group relative border-b border-slate-200 py-6 pl-16 last:border-b-0 md:border-b-0 md:px-5 md:pt-0 md:pb-0" style={{ animationDelay: `${index * 90}ms` }}>
                <div className={`absolute left-0 top-6 flex size-8 items-center justify-center rounded-full border text-[11px] font-bold md:left-5 md:top-3 ${index === 0 ? "border-cyan-500 bg-cyan-500 text-white shadow-[0_0_0_6px_#f5f8fb]" : "border-slate-300 bg-white text-slate-500 shadow-[0_0_0_6px_#f5f8fb]"}`}>
                  {item.step}
                </div>
                <div className="md:pt-16">
                  <p className="text-[11px] font-semibold uppercase tracking-[.13em] text-cyan-700/80">Step {item.step}</p>
                  <h3 className="mt-2 text-[17px] font-semibold text-slate-950">{item.title}</h3>
                  <p className="mt-2 max-w-[190px] text-[14px] leading-6 text-slate-600">{item.detail}</p>
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section id="visuals" className="scroll-mt-16 border-t border-slate-200 bg-white py-20 text-slate-950">
        <div className="mx-auto grid max-w-[1120px] gap-4 px-6 md:grid-cols-3">
          <Card className="border border-slate-200 bg-[#f8fafc] shadow-none">
            <p className="text-sm font-semibold text-slate-950">Live booking board</p>
            <p className="mt-2 text-[14px] leading-6 text-slate-600">
              Real-time flow with clear availability and payment state at a glance.
            </p>
          </Card>
          <Card className="border border-slate-200 bg-[#f8fafc] shadow-none">
            <p className="text-sm font-semibold text-slate-950">Role-based control</p>
            <p className="mt-2 text-[14px] leading-6 text-slate-600">
              Owners manage everything, staff see only what they need to do.
            </p>
          </Card>
          <Card className="border border-slate-200 bg-[#f8fafc] shadow-none">
            <p className="text-sm font-semibold text-slate-950">Simple operations</p>
            <p className="mt-2 text-[14px] leading-6 text-slate-600">
              Tasks, reminders, invoices, and check-ins without noisy navigation.
            </p>
          </Card>
        </div>
      </section>

      <section id="resources" className="relative overflow-hidden border-t border-slate-200 bg-[#eaf7fa] py-20 text-slate-950">
        <div className="pointer-events-none absolute inset-x-0 top-0 h-32 bg-[radial-gradient(ellipse_at_50%_0%,rgba(34,211,238,.2),transparent_68%)]" />
        <div className="mx-auto flex max-w-[1120px] flex-col items-center gap-5 px-6 text-center">
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-cyan-700">Ready when you are</p>
          <h2 className="max-w-[680px] text-[38px] font-display font-bold leading-tight text-slate-950">From story to action. Start from today.</h2>
          <div className="flex flex-wrap justify-center gap-3">
            <Button asChild size="lg" className="rounded-full bg-[#06263b] px-6 text-white hover:bg-[#0b3a58]">
              <a href="/app/register">Start your page</a>
            </Button>
            <Button asChild size="lg" className="rounded-full border border-[#06263b] !bg-[#06263b] px-6 !text-white hover:!bg-[#0b3a58]">
              <a href="/app/sign-in">Continue working <ArrowRight size={16} className="ml-1" /></a>
            </Button>
          </div>
        </div>
      </section>

      <footer className="border-t border-white/10 bg-[#06111d] py-10">
        <div className="mx-auto flex max-w-[1120px] flex-wrap items-center justify-between gap-4 px-6">
          <BookosLogo href="/" size="sm" wordmarkClassName="text-[16px] text-white" />
          <p className="t-small text-white/45">Powered by Tatos Technologies Pvt. Ltd.</p>
        </div>
      </footer>
    </main>
  );
}

function ProductShowcase() {
  return (
    <div className="hero-enter relative mx-auto mt-2 h-[420px] w-full max-w-[390px] sm:h-[500px] sm:max-w-[500px] md:mt-0 md:h-[465px] md:max-w-[480px] lg:mt-2 lg:h-[540px]" style={{ animationDelay: "250ms" }}>
      <p className="absolute left-1/2 top-1 z-30 -translate-x-1/2 whitespace-nowrap rounded-full border border-white/15 bg-[#07121e]/70 px-3 py-1 text-[9px] font-semibold tracking-[.13em] text-white/70 backdrop-blur">BOOKINGOS ON MOBILE</p>
      <div className="absolute bottom-6 left-[10%] right-[6%] h-12 rounded-[50%] bg-black/70 blur-2xl" />
      <div className="hero-phone-float-delayed absolute right-[3%] top-[19%] z-10 w-[45%] -rotate-[12deg] sm:right-[7%] sm:w-[40%] md:right-[4%]">
        <PhoneShell className="p-[7px]" label="Venue discovery">
          <VenuePhoneScreen />
        </PhoneShell>
      </div>
      <div className="hero-phone-float absolute left-[4%] top-[6%] z-20 w-[57%] rotate-[5deg] sm:left-[14%] sm:top-[4%] sm:w-[49%] md:left-[8%]">
        <PhoneShell className="p-[7px]" label="Operator dashboard">
          <OperatorPhoneScreen />
        </PhoneShell>
      </div>
    </div>
  );
}

function PhoneShell({ children, className, label }: { children: ReactNode; className?: string; label: string }) {
  return (
    <div className={`relative aspect-[.49] rounded-[30px] border border-white/55 bg-[linear-gradient(145deg,#f4f6f9_0%,#6a7179_15%,#121820_45%,#b7c0c6_100%)] shadow-[0_30px_50px_rgba(0,0,0,.58),0_0_40px_rgba(56,189,248,.16)] ${className ?? ""}`}>
      <div className="relative h-full overflow-hidden rounded-[24px] bg-[#f8fafc]">
        <div className="absolute left-1/2 top-2 z-20 h-4 w-[38%] -translate-x-1/2 rounded-full bg-[#0a1018]" />
        <span className="sr-only">{label}</span>
        {children}
      </div>
    </div>
  );
}

function OperatorPhoneScreen() {
  const metrics = [
    ["18", "Active slots", "#0ea5e9"],
    ["₹19.2k", "Today’s revenue", "#2563eb"],
    ["94%", "Check-ins complete", "#10b981"],
    ["6", "Pending tasks", "#f59e0b"],
  ];
  return (
    <div className="flex h-full flex-col bg-[#f8fafc] px-[7%] pt-[12%] text-[#0f172a]">
      <div className="flex items-center justify-between text-[7px] font-semibold"><span>9:41</span><span>● ● ●</span></div>
      <div className="mt-[9%] flex items-center gap-1.5 text-[10px] font-bold"><BookosMark size={17} className="rounded-[4px]" /> BookingOS</div>
      <p className="mt-[10%] text-[13px] font-bold tracking-[-.5px]">Good evening, Alex</p>
      <p className="mt-1 text-[6px] text-slate-500">Here’s what’s happening today.</p>
      <div className="mt-[7%] grid grid-cols-2 gap-1.5">
        {metrics.map(([value, caption, color]) => (
          <div key={caption} className="rounded-[8px] bg-white p-2 shadow-[0_3px_10px_rgba(15,23,42,.08)]">
            <span className="block text-[12px] font-bold">{value}</span><span className="mt-1 block text-[5px] leading-tight text-slate-500">{caption}</span>
            <span className="mt-1.5 block text-[5px] font-bold" style={{ color }}>↑ 12%</span>
          </div>
        ))}
      </div>
      <div className="mt-[8%] flex items-center justify-between"><p className="text-[8px] font-bold">Today’s bookings</p><span className="text-[5px] font-semibold text-blue-600">View all</span></div>
      <div className="mt-[3%] space-y-2">
        {["5v5 Turf Booking", "Team Practice", "Corporate Match"].map((booking, index) => (
          <div key={booking} className="flex items-center gap-1.5 border-b border-slate-100 pb-1.5"><span className="w-[20%] text-[5px] font-bold">{["6:00 PM", "7:00 PM", "8:30 PM"][index]}</span><span className="flex-1 text-[6px] font-semibold">{booking}<small className="block font-normal text-slate-400">Pitch {index + 1}</small></span><span className={`rounded-full px-1 py-0.5 text-[4px] font-bold ${index === 2 ? "bg-amber-100 text-amber-600" : "bg-emerald-100 text-emerald-600"}`}>{index === 2 ? "Pending" : "Confirmed"}</span></div>
        ))}
      </div>
      <div className="mt-auto -mx-[7%] grid grid-cols-5 border-t border-slate-100 bg-white px-[7%] py-[7%] text-center text-[5px] text-slate-400"><span className="font-bold text-blue-600">Home</span><span>Bookings</span><span>Calendar</span><span>Payments</span><span>More</span></div>
    </div>
  );
}

function VenuePhoneScreen() {
  return (
    <div className="flex h-full flex-col bg-[#f8fafc] px-[7%] pt-[12%] text-[#0f172a]">
      <div className="flex items-center justify-between text-[7px] font-semibold"><span>9:41</span><span>● ● ●</span></div>
      <p className="mt-[13%] text-[10px] font-bold">Find a Venue</p>
      <div className="mt-[7%] flex items-center gap-1 rounded-full bg-white px-2 py-1.5 shadow-sm"><Search size={8} className="text-slate-400" /><span className="text-[5px] text-slate-500">Kochi, Kerala</span></div>
      <div className="mt-[6%] flex gap-1 overflow-hidden text-[4px] font-semibold"><span className="rounded-full bg-[#0f2744] px-2 py-1 text-white">Football</span><span className="rounded-full bg-slate-200 px-2 py-1">Cricket</span><span className="rounded-full bg-slate-200 px-2 py-1">Badminton</span></div>
      <div className="mt-[7%] space-y-2.5">
        {["Turf Arena", "PlayHub Sports", "Game On Turf"].map((venue, index) => (
          <div key={venue} className="overflow-hidden rounded-[7px] bg-white shadow-[0_2px_10px_rgba(15,23,42,.08)]">
            <div className={`h-12 ${index === 1 ? "bg-[linear-gradient(135deg,#315a32,#071c2d)]" : "bg-[linear-gradient(135deg,#112c3a,#557838_50%,#0d1c2e)]"}`} />
            <div className="p-1.5"><span className="text-[6px] font-bold">{venue}</span><span className="block text-[4px] text-slate-500">5v5 · Floodlights</span><div className="mt-1 flex items-center justify-between"><span className="text-[5px] font-bold">₹{index === 0 ? "1,200" : "1,000"}/hr</span><span className="rounded-full bg-emerald-100 px-1 py-0.5 text-[4px] font-bold text-emerald-600">Available</span></div></div>
          </div>
        ))}
      </div>
      <div className="mt-auto -mx-[7%] grid grid-cols-4 border-t border-slate-100 bg-white px-[7%] py-[7%] text-center text-[5px] text-slate-400"><span>Home</span><span className="font-bold text-blue-600">Explore</span><span>Bookings</span><span>Profile</span></div>
    </div>
  );
}

function BookingFlowMock() {
  return (
    <div className="flex min-h-[300px]">
      <div className="w-24 shrink-0 border-r border-line bg-surface-shell p-2">
        <BookosMark size={18} className="rounded-[4px]" />
        <div className="mt-3 flex flex-col gap-2">
          {Array.from({ length: 7 }).map((_, i) => (
            <div
              key={i}
              className={i === 0 ? "h-2 w-16 rounded-full bg-brand/60" : "h-2 w-14 rounded-full bg-line"}
            />
          ))}
        </div>
      </div>
      <div className="flex flex-1 flex-col gap-2 p-3">
        <div className="h-3 w-28 rounded-full bg-line-strong/50" />
        <div className="grid grid-cols-3 gap-2">
          {Array.from({ length: 3 }).map((_, i) => (
            <div key={i} className="rounded-[6px] border border-line bg-surface-raised p-2">
              <div className="h-1.5 w-10 rounded-full bg-line" />
              <div className="mt-2 h-3 w-14 rounded-full bg-teal/70" />
            </div>
          ))}
        </div>
        <div className="mt-1 flex-1 rounded-[6px] border border-line bg-surface-raised p-2">
          <div className="h-2 w-20 rounded-full bg-line-strong/50" />
          <div className="mt-3 space-y-2">
            <div className="h-2 rounded-full bg-line" />
            <div className="h-2 w-4/5 rounded-full bg-line" />
            <div className="h-2 w-3/5 rounded-full bg-line" />
            <div className="h-6 w-32 rounded-md bg-brand/90" />
            <div className="h-2 w-40 rounded-full bg-line" />
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2 pt-1">
          <span className="rounded-full border border-line bg-line/30 p-1.5 text-[11px] text-ink-muted">Live slot cards</span>
          <span className="rounded-full border border-line bg-line/25 p-1.5 text-[11px] text-ink-muted">Invoice status</span>
        </div>
      </div>
    </div>
  );
}
