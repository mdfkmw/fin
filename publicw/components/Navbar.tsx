'use client'

import { useState } from 'react'
import Link from 'next/link'

const links = [
  { href: '/', label: 'Acasă' },
  { href: '#trasee', label: 'Trasee' },
  { href: '#rezervari', label: 'Rezervările Mele' },
  { href: '#contact', label: 'Contact' },
]

const NavLink = ({ href, children, onClick }: { href: string; children: React.ReactNode; onClick?: () => void }) => (
  <Link
    href={href}
    onClick={onClick}
    className="group relative block px-3 py-2 rounded-lg text-sm md:text-base text-white/80 hover:text-white transition"
  >
    {children}
    <span
      aria-hidden
      className="pointer-events-none absolute left-3 -bottom-0.5 h-[2px] rounded-full bg-gradient-to-r from-brand to-brandTeal origin-left w-[calc(100%-1.5rem)] transition-transform duration-500 ease-[cubic-bezier(0.19,1,0.22,1)] scale-x-0 group-hover:scale-x-100"
    />
    <span
      aria-hidden
      className="pointer-events-none absolute left-3 -bottom-0.5 h-[6px] rounded-full blur-sm opacity-0 bg-gradient-to-r from-brand/60 to-brandTeal/60 origin-left w-[calc(100%-1.5rem)] transition-all duration-500 ease-[cubic-bezier(0.19,1,0.22,1)] scale-x-0 group-hover:opacity-100 group-hover:scale-x-100"
    />
  </Link>
)

export default function Navbar() {
  const [open, setOpen] = useState(false)

  return (
    <header className="w-full sticky top-0 z-30 backdrop-blur supports-[backdrop-filter]:bg-black/40">
      <div className="max-w-6xl mx-auto flex items-center justify-between py-4 px-4">
        <Link href="/" className="flex items-center gap-2 font-semibold text-white">
          <span className="text-primary">✈</span>
          <span className="text-xl">VoyageBus</span>
        </Link>
        <nav className="hidden md:flex items-center gap-1">
          {links.map((link) => (
            <NavLink key={link.href} href={link.href}>
              {link.label}
            </NavLink>
          ))}
        </nav>
        <button
          type="button"
          className="md:hidden inline-flex items-center justify-center rounded-xl bg-white/10 px-3 py-2 text-sm text-white/80 hover:text-white hover:bg-white/20 transition"
          onClick={() => setOpen((prev) => !prev)}
          aria-expanded={open}
          aria-controls="mobile-nav"
          aria-label="Deschide meniul"
        >
          <span className="sr-only">Meniu</span>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className="size-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            {open ? (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M6 18L18 6M6 6l12 12" />
            ) : (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 6h16M4 12h16M4 18h16" />
            )}
          </svg>
        </button>
      </div>
      {open && (
        <div
          id="mobile-nav"
          className="md:hidden px-4 pb-4"
        >
          <div className="rounded-2xl border border-white/10 bg-black/50 backdrop-blur p-3 space-y-1">
            {links.map((link) => (
              <NavLink key={link.href} href={link.href} onClick={() => setOpen(false)}>
                {link.label}
              </NavLink>
            ))}
          </div>
        </div>
      )}
    </header>
  )
}
