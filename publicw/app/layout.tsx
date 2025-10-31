import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'PRIS COM Travel',
  description: 'Transport persoane • Rezervări online • Confort și siguranță',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ro">
      <body>{children}</body>
    </html>
  )
}
