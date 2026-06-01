import Image from "next/image";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { platformPills, proofItems } from "@/components/landing/landing-data";

/** Presents the core promise and the primary repository connection action. */
export function HeroSection() {
  return (
    <section className="overflow-hidden border-b border-[var(--landing-line)] bg-[var(--landing-cream)] px-5 pb-14 pt-16 md:pt-20">
      <div className="mx-auto flex max-w-[1180px] flex-col items-center text-center">
        <div className="mb-8 flex flex-wrap justify-center gap-3">
          {platformPills.map((pill) => (
            <span
              key={pill}
              className="rounded-full border border-[var(--landing-line)] bg-[var(--landing-paper)] px-4 py-2 text-[14px] font-medium text-[var(--landing-muted)]"
            >
              {pill}
            </span>
          ))}
        </div>
        <h1 className="max-w-[980px] text-balance text-[54px] font-semibold leading-[0.94] text-[var(--landing-ink)] md:text-[88px] lg:text-[112px]">
          The simplest way to turn specs into shipped work
        </h1>
        <p className="mt-7 max-w-[680px] text-pretty text-[20px] leading-8 text-[var(--landing-muted)] md:text-[24px] md:leading-9">
          Say goodbye to scattered AI work. Meet Symphonia - the workspace where
          specs become reviewed code.
        </p>
        <div className="mt-9 flex flex-col items-center gap-4 sm:flex-row">
          <Link
            href="/dashboard"
            className="inline-flex h-12 items-center gap-2 rounded-full bg-[var(--landing-blue)] px-6 text-[16px] font-semibold text-white shadow-[0_14px_30px_rgba(37,99,235,0.24)] transition hover:-translate-y-0.5 hover:bg-[var(--landing-blue-dark)]"
          >
            Connect repository
            <ArrowRight className="h-4 w-4" />
          </Link>
        </div>
        <HeroArtwork />
        <ProofStrip />
      </div>
    </section>
  );
}

/** Shows the uploaded Symphonia hero illustration in the Bear-style art position. */
function HeroArtwork() {
  return (
    <div className="relative mt-12 w-full max-w-[1060px]">
      <Image
        src="/images/symphonia-hero.png"
        alt="Minimal line illustration of a developer desk for Symphonia."
        width={1376}
        height={768}
        priority
        className="mx-auto h-auto w-full"
        sizes="(max-width: 768px) 96vw, 1060px"
      />
    </div>
  );
}

/** Summarizes the most important trust signals directly below the hero artwork. */
function ProofStrip() {
  return (
    <div className="mt-4 grid w-full max-w-[840px] gap-3 sm:grid-cols-3">
      {proofItems.map((item) => (
        <div
          key={item}
          className="border-t border-[var(--landing-line)] px-4 py-5 text-[14px] font-semibold text-[var(--landing-muted)]"
        >
          {item}
        </div>
      ))}
    </div>
  );
}
