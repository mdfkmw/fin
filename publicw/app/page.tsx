'use client'

import { useEffect, useMemo, useState } from 'react'
import Navbar from '@/components/Navbar'
import SearchCard, { type SearchValues } from '@/components/SearchCard'
import SeatModal from '@/components/SeatModal'
import {
  ApiError,
  createPublicReservation,
  fetchRoutesMeta,
  searchPublicTrips,
  type PromoApplyPayload,
  type PublicTrip,
  type RoutesMeta,
} from '@/lib/api'

type ExtendedTrip = PublicTrip & { fromName: string; toName: string }

type FeedbackState = { type: 'success' | 'error'; message: string } | null

export default function Page() {
  const [meta, setMeta] = useState<RoutesMeta | null>(null)
  const [metaLoading, setMetaLoading] = useState(true)
  const [metaError, setMetaError] = useState<string | null>(null)

  const [searchValues, setSearchValues] = useState<SearchValues | null>(null)
  const [trips, setTrips] = useState<PublicTrip[]>([])
  const [tripsLoading, setTripsLoading] = useState(false)
  const [tripsError, setTripsError] = useState<string | null>(null)

  const [open, setOpen] = useState(false)
  const [activeTrip, setActiveTrip] = useState<ExtendedTrip | null>(null)
  const [feedback, setFeedback] = useState<FeedbackState>(null)

  useEffect(() => {
    let ignore = false
    setMetaLoading(true)
    setMetaError(null)
    fetchRoutesMeta()
      .then((data) => {
        if (ignore) return
        setMeta(data)
      })
      .catch((err: any) => {
        if (ignore) return
        setMetaError(err?.message || 'Nu am putut încărca stațiile disponibile.')
      })
      .finally(() => {
        if (!ignore) setMetaLoading(false)
      })

    return () => {
      ignore = true
    }
  }, [])

  const stationNameById = useMemo(() => {
    const map = new Map<number, string>()
    meta?.stations.forEach((st) => map.set(st.id, st.name))
    return map
  }, [meta])

  const onlineRoutes = useMemo(() => meta?.routes ?? [], [meta])

  const performSearch = async (values: SearchValues) => {
    setTripsLoading(true)
    setTripsError(null)
    try {
      const data = await searchPublicTrips({
        fromStationId: values.fromStationId,
        toStationId: values.toStationId,
        date: values.date,
        passengers: values.passengers,
      })
      setTrips(data)
    } catch (err: any) {
      const message = err?.message || 'Nu am putut căuta cursele disponibile.'
      setTripsError(message)
      setTrips([])
    } finally {
      setTripsLoading(false)
    }
  }

  const handleSearch = async (values: SearchValues) => {
    setFeedback(null)
    setSearchValues(values)
    await performSearch(values)
  }

  const handleReserve = (trip: PublicTrip) => {
    const fromName = stationNameById.get(trip.board_station_id) || 'Stație'
    const toName = stationNameById.get(trip.exit_station_id) || 'Stație'
    setActiveTrip({ ...trip, fromName, toName })
    setOpen(true)
  }

  const handleConfirm = async ({
    seats,
    contact,
    promo,
  }: {
    seats: number[]
    contact: { name: string; phone: string }
    promo?: PromoApplyPayload | null
  }) => {
    if (!activeTrip) return
    try {
      const response = await createPublicReservation({
        trip_id: activeTrip.trip_id,
        board_station_id: activeTrip.board_station_id,
        exit_station_id: activeTrip.exit_station_id,
        seats,
        contact,
        promo: promo ?? null,
      })
      const discount = response.discount_total && response.discount_total > 0
        ? ` Reducere aplicată: -${formatPrice(response.discount_total, response.currency || 'RON')}.`
        : ''
      setFeedback({
        type: 'success',
        message: `Rezervarea a fost înregistrată! Te vom contacta pentru confirmarea locurilor.${discount}`,
      })
      setOpen(false)
      setActiveTrip(null)
      if (searchValues) {
        await performSearch(searchValues)
      }
    } catch (err: any) {
      if (err instanceof ApiError) {
        throw new Error(err.message)
      }
      if (err instanceof Error) {
        throw err
      }
      throw new Error('Nu am putut finaliza rezervarea.')
    }
  }

  const tripsWithNames: ExtendedTrip[] = useMemo(() => {
    return trips.map((trip) => ({
      ...trip,
      fromName: stationNameById.get(trip.board_station_id) || 'Stație',
      toName: stationNameById.get(trip.exit_station_id) || 'Stație',
    }))
  }, [trips, stationNameById])

  return (
    <main>
      <Navbar />
      <section className="hero-aurora pb-12 md:pb-20">
        <div className="max-w-6xl mx-auto px-4 pt-16 md:pt-24 relative z-10 space-y-10">
          <div className="text-center md:text-left md:flex md:flex-col md:items-start md:space-y-6 space-y-4">
            <div className="inline-flex items-center gap-2 rounded-full bg-white/10 px-4 py-1 text-sm font-semibold text-white/80 mx-auto md:mx-0">
              <span className="size-2 rounded-full bg-brand animate-pulse" aria-hidden />
              Gata de rezervare în mai puțin de un minut
            </div>
            <h1 className="text-[36px] leading-tight md:text-[56px] font-extrabold tracking-tight">
              Rezervări rapide, gândite pentru mobil și drumuri fără stres
            </h1>
            <p className="text-white/80 text-base md:text-lg max-w-2xl mx-auto md:mx-0">
              Alege traseul, verifică locurile libere în timp real și confirmă din mers. Interfața este optimizată pentru ecrane mici, astfel încât poți finaliza rezervarea cu o mână, oriunde te-ai afla.
            </p>
            <div className="flex flex-wrap items-center justify-center md:justify-start gap-3 text-sm text-white/70">
              <span className="inline-flex items-center gap-2 rounded-full bg-white/10 px-4 py-2">
                <span className="text-brand">◎</span>
                Hartă interactivă a locurilor
              </span>
              <span className="inline-flex items-center gap-2 rounded-full bg-white/10 px-4 py-2">
                <span className="text-brand">💳</span>
                Coduri de reducere dinamic validate din bază de date
              </span>
              <span className="inline-flex items-center gap-2 rounded-full bg-white/10 px-4 py-2">
                <span className="text-brand">📱</span>
                UI fluid pe orice telefon
              </span>
            </div>
          </div>
          <div className="bg-black/30 rounded-3xl ring-1 ring-white/10 p-3 shadow-[0_25px_50px_-12px_rgba(15,23,42,0.6)]">
            <SearchCard
              stations={meta?.stations ?? []}
              relations={meta?.relations ?? []}
              loading={metaLoading}
              onSearch={handleSearch}
            />
            {metaError && <p className="text-sm text-rose-300 mt-3 text-center">{metaError}</p>}
          </div>
        </div>
      </section>

      <section className="max-w-6xl mx-auto px-4 mt-10 md:mt-12" id="rezervari">
        <div className="flex items-center justify-between flex-wrap gap-3">
          <h2 className="text-2xl md:text-3xl font-bold">Rezultatele căutării</h2>
          {searchValues && (
            <div className="text-sm text-white/60">
              {stationNameById.get(searchValues.fromStationId) || '—'} →{' '}
              {stationNameById.get(searchValues.toStationId) || '—'} · {formatRoDate(searchValues.date)}
            </div>
          )}
        </div>

        {feedback && feedback.type === 'success' && (
          <div className="mt-6 rounded-2xl bg-emerald-500/15 border border-emerald-400/40 text-emerald-200 px-5 py-4 text-sm">
            {feedback.message}
          </div>
        )}

        {tripsError && (
          <div className="mt-6 rounded-2xl bg-rose-500/10 border border-rose-400/40 text-rose-200 px-5 py-4 text-sm">
            {tripsError}
          </div>
        )}

        {tripsLoading && (
          <div className="mt-10 text-center text-white/70">Se încarcă rezultatele...</div>
        )}

        {!tripsLoading && !tripsError && tripsWithNames.length === 0 && searchValues && (
          <div className="mt-10 text-center text-white/70">Nu există curse disponibile pentru criteriile selectate.</div>
        )}

        <div className="mt-6 grid gap-6">
          {tripsWithNames.map((trip) => (
            <article key={trip.trip_id} className="trip-card overflow-hidden">
              <div className="flex flex-col md:flex-row md:items-stretch">
                <div className="flex-1 p-5 md:p-7 space-y-6">
                  <div className="flex items-center gap-4 flex-wrap">
                    <div>
                      <div className="text-white/80 text-sm">{trip.fromName}</div>
                      <div className="text-3xl font-bold text-brand">{trip.departure_time}</div>
                    </div>
                    <div className="flex-1 text-center route-line-demo min-w-[120px]">
                      <span className="text-sm">
                        {trip.arrival_time ? `${trip.departure_time} → ${trip.arrival_time}` : 'Durată variabilă'}
                      </span>
                      <div className="line" />
                    </div>
                    <div>
                      <div className="text-white/80 text-sm">{trip.toName}</div>
                      <div className="text-3xl font-bold text-brand">
                        {trip.arrival_time || '—'}
                      </div>
                    </div>
                  </div>
                  <div className="grid sm:grid-cols-3 gap-3 text-sm text-white/70">
                    <div>
                      <span className="text-white/50">Rută:</span> {trip.route_name}
                    </div>
                    <div>
                      <span className="text-white/50">Locuri disponibile:</span> {trip.available_seats ?? 'n/a'}
                    </div>
                    <div>
                      <span className="text-white/50">Direcție:</span> {trip.direction === 'retur' ? 'Retur' : 'Tur'}
                    </div>
                  </div>
                </div>
                <div className="md:w-[220px] bg-white/5 border-t md:border-l border-white/10 grid place-items-center p-6">
                  <div className="text-center space-y-2">
                    <div className="inline-flex items-baseline justify-center rounded-full bg-brand/20 px-6 py-4">
                      <div className="text-3xl font-extrabold">{formatPrice(trip.price, trip.currency)}</div>
                    </div>
                    <div className="text-xs text-white/70">per loc</div>
                    <button
                      className="btn-primary w-full"
                      onClick={() => handleReserve(trip)}
                      disabled={!trip.can_book}
                    >
                      {trip.can_book ? 'Alege locuri' : 'Indisponibil'}
                    </button>
                  </div>
                </div>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="max-w-6xl mx-auto px-4 mt-16" id="trasee">
        <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div>
            <h2 className="text-2xl md:text-3xl font-bold">Trasee disponibile</h2>
            <p className="text-white/70 text-sm md:text-base">
              Traseele pe care le poți rezerva direct online.
            </p>
          </div>
          <div className="text-sm text-white/60">
            {metaLoading ? 'Se încarcă traseele...' : `${onlineRoutes.length} trasee disponibile`}
          </div>
        </div>
        {metaError ? (
          <div className="mt-4 rounded-2xl bg-rose-500/10 border border-rose-400/40 px-4 py-3 text-sm text-rose-200">
            {metaError}
          </div>
        ) : (
          <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {onlineRoutes.map((route) => {
              const start = route.stations[0] ?? '—'
              const end = route.stations[route.stations.length - 1] ?? '—'
              const middle = route.stations.slice(1, -1)
              return (
                <article
                  key={route.id}
                  className="rounded-2xl border border-white/10 bg-white/5 p-5 shadow-soft backdrop-blur"
                >
                  <h3 className="text-lg font-semibold text-white">{route.name}</h3>
                  <p className="mt-2 text-sm text-white/70">
                    {start} → {end}
                  </p>
                  {middle.length > 0 && (
                    <p className="mt-3 text-xs text-white/50">
                      Stații intermediare: {middle.join(', ')}
                    </p>
                  )}
                </article>
              )
            })}
            {!metaLoading && onlineRoutes.length === 0 && (
              <div className="col-span-full rounded-2xl border border-white/10 bg-white/5 px-5 py-6 text-center text-sm text-white/60">
                Momentan nu sunt trasee disponibile online.
              </div>
            )}
          </div>
        )}
      </section>

      <footer className="mt-20 border-t border-white/10">
        <div className="max-w-6xl mx-auto px-4 py-10 text-white/60 text-sm">
          © {new Date().getFullYear()} PRIS COM Travel — Toate drepturile rezervate.
        </div>
      </footer>

      <SeatModal
        isOpen={open}
        onClose={() => {
          setOpen(false)
          setActiveTrip(null)
        }}
        onConfirm={handleConfirm}
        trip={activeTrip}
        travelDate={searchValues?.date ?? null}
      />
    </main>
  )
}

function formatRoDate(iso: string) {
  try {
    const d = new Date(iso)
    return d.toLocaleDateString('ro-RO', { day: '2-digit', month: 'short', year: 'numeric' })
  } catch {
    return iso
  }
}

function formatPrice(value: number | null, currency: string | null) {
  if (!value || value <= 0) return '-'
  try {
    return new Intl.NumberFormat('ro-RO', {
      style: 'currency',
      currency: currency || 'RON',
      minimumFractionDigits: 0,
    }).format(value)
  } catch {
    return `${value} ${currency || 'RON'}`
  }
}
