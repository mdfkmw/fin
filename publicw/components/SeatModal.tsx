'use client'

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { IntentInfo, PromoApplyPayload, PublicTrip, SeatMapResponse, SeatVehicle } from '@/lib/api'
import { createIntent, deleteIntent, fetchTripIntents, fetchTripSeatMap, validatePromoCode } from '@/lib/api'

type ContactInfo = {
  name: string
  phone: string
}

type ConfirmPayload = {
  seats: number[]
  contact: ContactInfo
  promo?: PromoApplyPayload | null
}

export type SeatModalProps = {
  isOpen: boolean
  onClose: () => void
  onConfirm: (payload: ConfirmPayload) => Promise<void>
  trip: (PublicTrip & { fromName: string; toName: string }) | null
  travelDate?: string | null
}

const VEHICLE_TAB_CLASS = 'px-4 py-2 rounded-full text-sm font-semibold transition-colors'

export default function SeatModal({ isOpen, onClose, onConfirm, trip, travelDate }: SeatModalProps) {
  const [seatData, setSeatData] = useState<SeatMapResponse | null>(null)
  const [activeVehicle, setActiveVehicle] = useState<number | null>(null)
  const [selectedSeats, setSelectedSeats] = useState<number[]>([])
  const selectedSeatsRef = useRef<number[]>([])
  const [contact, setContact] = useState<ContactInfo>({ name: '', phone: '' })
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [promoCode, setPromoCode] = useState('')
  const [promoFeedback, setPromoFeedback] = useState<string | null>(null)
  const [promoLoading, setPromoLoading] = useState(false)
  const [appliedPromo, setAppliedPromo] = useState<PromoApplyPayload | null>(null)
  const [seatFeedback, setSeatFeedback] = useState<string | null>(null)
  const [intentHolds, setIntentHolds] = useState<Map<number, 'mine' | 'other'>>(new Map())
  const lastSeatCountRef = useRef(0)
  const intentTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const seatTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const lastTripIdRef = useRef<number | null>(null)

  const refreshIntents = useCallback(async (): Promise<Map<number, 'mine' | 'other'> | null> => {
    if (!trip) return null
    try {
      const data = await fetchTripIntents(trip.trip_id)
      const map = new Map<number, 'mine' | 'other'>()
      data.forEach((intent: IntentInfo) => {
        const seatId = Number(intent.seat_id)
        if (!Number.isFinite(seatId)) return
        map.set(seatId, intent.is_mine === 1 ? 'mine' : 'other')
      })
      setIntentHolds(map)
      return map
    } catch {
      return null
    }
  }, [trip])

  const reloadSeatData = useCallback(async (showSpinner = false) => {
    if (!trip) return
    if (showSpinner) {
      setLoading(true)
      setError(null)
    }
    try {
      const data = await fetchTripSeatMap(trip.trip_id, trip.board_station_id, trip.exit_station_id)
      setSeatData(data)
      setActiveVehicle((prev) => {
        if (!data?.vehicles?.length) return null
        if (prev && data.vehicles.some((veh) => veh.vehicle_id === prev)) {
          return prev
        }
        return data.vehicles[0]?.vehicle_id ?? null
      })
    } catch (err: any) {
      if (showSpinner) {
        setError(err?.message || 'Nu am putut încărca diagrama de locuri.')
      }
    } finally {
      if (showSpinner) {
        setLoading(false)
      }
    }
  }, [trip])

  useEffect(() => {
    if (!isOpen || !trip) return

    let cancelled = false
    setError(null)
    setSeatData(null)
    setSelectedSeats([])
    setContact({ name: '', phone: '' })
    setSeatFeedback(null)
    setIntentHolds(new Map())

    reloadSeatData(true).then(() => {
      if (!cancelled) {
        refreshIntents()
      }
    })

    if (intentTimerRef.current) {
      clearInterval(intentTimerRef.current)
      intentTimerRef.current = null
    }
    if (seatTimerRef.current) {
      clearInterval(seatTimerRef.current)
      seatTimerRef.current = null
    }

    intentTimerRef.current = setInterval(() => {
      refreshIntents()
    }, 2500)

    seatTimerRef.current = setInterval(() => {
      reloadSeatData(false)
    }, 7000)

    return () => {
      cancelled = true
      if (intentTimerRef.current) {
        clearInterval(intentTimerRef.current)
        intentTimerRef.current = null
      }
      if (seatTimerRef.current) {
        clearInterval(seatTimerRef.current)
        seatTimerRef.current = null
      }
    }
  }, [isOpen, trip, reloadSeatData, refreshIntents])

  useEffect(() => {
    if (!isOpen) {
      setSeatData(null)
      setActiveVehicle(null)
      setSelectedSeats([])
      setSubmitError(null)
      setContact({ name: '', phone: '' })
      setPromoCode('')
      setPromoFeedback(null)
      setAppliedPromo(null)
      setPromoLoading(false)
      setSeatFeedback(null)
      setIntentHolds(new Map())

      const tripId = trip?.trip_id ?? lastTripIdRef.current
      const seatsToRelease = selectedSeatsRef.current.slice()
      if (tripId && seatsToRelease.length) {
        seatsToRelease.forEach((seatId) => {
          deleteIntent(tripId, seatId).catch(() => {})
        })
      }
      selectedSeatsRef.current = []
    }
  }, [isOpen, trip])

  useEffect(() => {
    selectedSeatsRef.current = selectedSeats
  }, [selectedSeats])

  useEffect(() => {
    if (trip?.trip_id) {
      lastTripIdRef.current = trip.trip_id
    }
  }, [trip])

  useEffect(() => {
    if (!trip || !seatData) return

    const seatLookup = new Map<number, { isAvailable: boolean; holdStatus: 'mine' | 'other' | null }>()
    seatData.vehicles?.forEach((veh) => {
      veh.seats.forEach((seat) => {
        seatLookup.set(seat.id, { isAvailable: seat.is_available, holdStatus: seat.hold_status ?? null })
      })
    })

    const toRemove: number[] = []
    selectedSeatsRef.current.forEach((seatId) => {
      const seat = seatLookup.get(seatId)
      const hold = intentHolds.get(seatId) ?? seat?.holdStatus ?? null
      const heldByOther = hold === 'other'
      const heldByMe = hold === 'mine'
      if (!seat || heldByOther || (!seat.isAvailable && !heldByMe)) {
        toRemove.push(seatId)
      }
    })

    if (!toRemove.length) return

    const tripId = trip.trip_id
    setSelectedSeats((prev) => prev.filter((id) => !toRemove.includes(id)))
    toRemove.forEach((seatId) => {
      deleteIntent(tripId, seatId).catch(() => {})
    })
    setSeatFeedback((prev) => prev || 'Unele locuri au devenit indisponibile și au fost eliminate din selecție.')
  }, [seatData, intentHolds, trip])

  useEffect(() => {
    const prevCount = lastSeatCountRef.current
    if (appliedPromo && prevCount !== selectedSeats.length) {
      setAppliedPromo(null)
      if (selectedSeats.length > 0) {
        setPromoFeedback('Selecția locurilor s-a schimbat. Aplică din nou codul de reducere.')
      } else {
        setPromoFeedback(null)
      }
    }
    lastSeatCountRef.current = selectedSeats.length
  }, [selectedSeats.length, appliedPromo])

  const currentVehicle = useMemo<SeatVehicle | null>(() => {
    if (!seatData || !Array.isArray(seatData.vehicles)) return null
    if (activeVehicle) {
      return seatData.vehicles.find((veh) => veh.vehicle_id === activeVehicle) ?? seatData.vehicles[0] ?? null
    }
    return seatData.vehicles[0] ?? null
  }, [seatData, activeVehicle])

  const seatLookup = useMemo(() => {
    const map = new Map<number, string>()
    if (seatData?.vehicles) {
      for (const veh of seatData.vehicles) {
        for (const seat of veh.seats) {
          map.set(seat.id, seat.label)
        }
      }
    }
    return map
  }, [seatData])

  const maxRow = useMemo(() => {
    if (!currentVehicle) return 0
    return Math.max(0, ...currentVehicle.seats.map((seat) => Number(seat.row ?? 0)))
  }, [currentVehicle])

  const maxCol = useMemo(() => {
    if (!currentVehicle) return 0
    return Math.max(1, ...currentVehicle.seats.map((seat) => Number(seat.seat_col ?? 1)))
  }, [currentVehicle])

  const subtotal = useMemo(() => {
    if (!trip?.price || !selectedSeats.length) return 0
    return trip.price * selectedSeats.length
  }, [trip, selectedSeats])

  const discountAmount = useMemo(() => {
    if (!appliedPromo) return 0
    return Math.min(Number(appliedPromo.discount_amount || 0), subtotal)
  }, [appliedPromo, subtotal])

  const totalDue = useMemo(() => {
    return Math.max(0, subtotal - discountAmount)
  }, [subtotal, discountAmount])

  const toggleSeat = useCallback(async (seatId: number) => {
    if (!trip || !currentVehicle) return
    const seat = currentVehicle.seats.find((s) => s.id === seatId)
    if (!seat) return
    if (seat.seat_type === 'driver' || seat.seat_type === 'guide') return

    const holdStatus = intentHolds.get(seatId) ?? seat.hold_status ?? null
    const heldByOther = holdStatus === 'other'
    const isSelected = selectedSeatsRef.current.includes(seatId)

    if (heldByOther) {
      setSeatFeedback('Locul este rezervat temporar de alt client.')
      return
    }

    if (isSelected) {
      setSelectedSeats((prev) => prev.filter((id) => id !== seatId))
      try {
        await deleteIntent(trip.trip_id, seatId)
      } catch {}
      await refreshIntents()
      setSeatFeedback(null)
      return
    }

    try {
      await createIntent({ trip_id: trip.trip_id, seat_id: seatId })
      setSelectedSeats((prev) => [...prev, seatId])
      await refreshIntents()
      setSeatFeedback(null)
    } catch (err: any) {
      setSeatFeedback(err?.message || 'Locul a fost selectat de un alt călător.')
      await reloadSeatData(false)
      await refreshIntents()
    }
  }, [trip, currentVehicle, intentHolds, refreshIntents, reloadSeatData])

  const handleSubmit = async () => {
    if (!trip || !selectedSeats.length) return
    if (!contact.name.trim() || !contact.phone.trim()) {
      setSubmitError('Completează numele și telefonul pentru confirmare.')
      return
    }
    setSubmitting(true)
    setSubmitError(null)
    try {
      await onConfirm({
        seats: selectedSeats,
        contact: {
          name: contact.name.trim(),
          phone: contact.phone.trim(),
        },
        promo: appliedPromo,
      })
    } catch (err: any) {
      setSubmitError(err?.message || 'Nu am putut finaliza rezervarea. Încearcă din nou.')
      setSubmitting(false)
      return
    }
    setSubmitting(false)
  }

  const handleApplyPromo = async () => {
    if (!trip) return
    const code = promoCode.trim()
    if (!code) {
      setPromoFeedback('Introdu un cod de reducere înainte de a aplica.')
      return
    }
    if (!selectedSeats.length) {
      setPromoFeedback('Selectează locurile înainte de a aplica un cod.')
      return
    }
    if (!trip.price || trip.price <= 0) {
      setPromoFeedback('Codurile promoționale se pot aplica doar curselor cu tarif afișat.')
      return
    }

    setPromoLoading(true)
    setPromoFeedback(null)
    try {
      const result = await validatePromoCode({
        code,
        trip_id: trip.trip_id,
        board_station_id: trip.board_station_id,
        exit_station_id: trip.exit_station_id,
        seat_count: selectedSeats.length,
        phone: contact.phone,
      })

      if (!result.valid || !result.promo_code_id || !result.discount_amount) {
        setAppliedPromo(null)
        setPromoFeedback(result.reason || 'Codul nu este valabil pentru această rezervare.')
      } else {
        setAppliedPromo({
          code: (result.code || code).toUpperCase(),
          promo_code_id: result.promo_code_id,
          discount_amount: Number(result.discount_amount),
          value_off: Number(result.value_off ?? result.discount_amount),
        })
        setPromoFeedback(
          `Reducere aplicată: -${formatPrice(Number(result.discount_amount), trip.currency)}`
        )
      }
    } catch (err: any) {
      setAppliedPromo(null)
      setPromoFeedback(err?.message || 'Nu am putut valida codul. Încearcă din nou.')
    } finally {
      setPromoLoading(false)
    }
  }

  const handleRemovePromo = () => {
    setAppliedPromo(null)
    setPromoFeedback('Codul a fost eliminat.')
  }

  if (!isOpen || !trip) return null

  return (
    <div className="fixed inset-0 z-50">
      <div className="absolute inset-0 bg-black/60" onClick={onClose} />
      <div className="absolute inset-0 grid place-items-center p-4">
        <div className="w-full max-w-5xl rounded-2xl bg-[#1b2338] ring-1 ring-white/10 shadow-soft overflow-hidden">
          <div className="flex items-center justify-between px-6 py-4 bg-black/20">
            <div>
              <h3 className="text-2xl font-extrabold">Selectează Locurile Tale</h3>
              <p className="text-sm text-white/60 mt-1">
                {trip.fromName} → {trip.toName}
                {travelDate ? ` · ${formatRoDate(travelDate)}` : ''}
              </p>
            </div>
            <button onClick={onClose} className="text-white/70 hover:text-white text-xl" aria-label="Închide">
              ×
            </button>
          </div>

          <div className="px-6 py-4 border-b border-white/10 flex flex-wrap items-center gap-4 text-sm">
            <Legend color="bg-transparent ring-1 ring-white/30" label="Disponibil" />
            <Legend color="bg-brand text-white" label="Selectat" />
            <Legend color="bg-amber-500/80 text-black" label="În curs de rezervare" />
            <Legend color="bg-white/20" label="Ocupat" />
          </div>

          <div className="max-h-[70vh] overflow-y-auto px-6 py-6 space-y-6">
            {loading && <div className="text-center text-white/70">Se încarcă diagrama locurilor...</div>}
            {error && <div className="text-center text-rose-400 font-semibold">{error}</div>}
            {seatFeedback && !loading && !error && (
              <div className="rounded-xl bg-amber-500/15 px-4 py-2 text-sm text-amber-100">
                {seatFeedback}
              </div>
            )}

            {!loading && !error && currentVehicle && (
              <div className="space-y-4">
                {seatData && seatData.vehicles.length > 1 && (
                  <div className="flex flex-wrap gap-3">
                    {seatData.vehicles.map((veh) => {
                      const active = veh.vehicle_id === (currentVehicle?.vehicle_id ?? null)
                      return (
                        <button
                          key={veh.vehicle_id}
                          onClick={() => setActiveVehicle(veh.vehicle_id)}
                          className={`${VEHICLE_TAB_CLASS} ${active ? 'bg-brand text-white' : 'bg-white/10 text-white/70 hover:bg-white/20'}`}
                        >
                          {veh.vehicle_name}
                          {veh.is_primary ? ' · Principal' : ''}
                        </button>
                      )
                    })}
                  </div>
                )}

                <div className="mx-auto w-full overflow-x-auto">
                  <div
                    className="mx-auto rounded-2xl bg-[#151c2f] ring-1 ring-white/10 p-6"
                    style={{
                      display: 'grid',
                      gridTemplateColumns: `repeat(${maxCol || 1}, minmax(3.5rem, 4rem))`,
                      gridTemplateRows: `repeat(${maxRow + 1}, 4rem)`,
                      gap: '0.75rem',
                      justifyContent: 'center',
                    }}
                  >
                    {currentVehicle.seats.map((seat) => {
                      const hold = intentHolds.get(seat.id) ?? seat.hold_status ?? null
                      const heldByOther = hold === 'other'
                      const heldByMe = hold === 'mine'
                      const isSelected = selectedSeats.includes(seat.id)
                      const isDriver = seat.seat_type === 'driver' || seat.seat_type === 'guide'
                      const baseUnavailable = seat.status === 'full' || (!seat.is_available && !heldByMe)
                      const isUnavailable = isDriver || heldByOther || baseUnavailable

                      const baseClasses = [
                        'seat',
                        'rounded-xl text-sm font-semibold grid place-items-center transition-all duration-200 ease-out',
                        'shadow-[inset_0_0_0_1px_rgba(255,255,255,0.15)]',
                      ]

                      let stateClasses = ''
                      if (isDriver) {
                        stateClasses = 'bg-white/10 text-white/60 cursor-not-allowed'
                      } else if (heldByOther) {
                        stateClasses = 'bg-amber-500/80 text-black cursor-not-allowed'
                      } else if (isSelected || heldByMe) {
                        stateClasses = 'bg-brand text-white shadow-[0_0_14px_rgba(47,168,79,0.7)] scale-105'
                      } else if (baseUnavailable) {
                        stateClasses = 'bg-white/15 text-white/40 cursor-not-allowed'
                      } else if (seat.status === 'partial') {
                        stateClasses = 'bg-amber-400/80 text-black hover:bg-amber-400'
                      } else {
                        stateClasses = 'bg-white/10 text-white hover:bg-white/20 hover:scale-105'
                      }

                      return (
                        <button
                          key={seat.id}
                          onClick={() => toggleSeat(seat.id)}
                          disabled={isUnavailable}
                          className={[...baseClasses, stateClasses, isSelected ? 'ring-2 ring-white' : ''].join(' ')}
                          style={{
                            gridColumnStart: (seat.seat_col || 1),
                            gridRowStart: (seat.row ?? 0) + 1,
                          }}
                        >
                          {seat.label}
                        </button>
                      )
                    })}
                  </div>
                </div>

                <div className="rounded-2xl bg-white/5 ring-1 ring-white/10 p-5 space-y-4">
                  <div className="grid md:grid-cols-2 gap-4 text-sm">
                    <div className="space-y-1">
                      <div className="text-white/70">Traseu selectat</div>
                      <div className="font-medium">{trip.fromName} → {trip.toName}</div>
                    </div>
                    <div className="space-y-1 md:text-right">
                      <div className="text-white/70">Plecare</div>
                      <div className="font-medium">{trip.departure_time}{travelDate ? `, ${formatRoDate(travelDate)}` : ''}</div>
                    </div>
                    <div className="space-y-1">
                      <div className="text-white/70">Locuri selectate</div>
                      <div className="font-medium">
                        {selectedSeats.length ? selectedSeats.map((id) => seatLookup.get(id)).filter(Boolean).join(', ') : '-'}
                      </div>
                    </div>
                    <div className="space-y-1 md:text-right">
                      <div className="text-white/70">Total estimat</div>
                      <div className="text-lg font-extrabold">
                        {subtotal > 0 ? formatPrice(subtotal, trip.currency) : '0'}
                      </div>
                    </div>
                  </div>

                  <div className="space-y-4 max-w-xl">
                    <div className="space-y-2">
                      <label htmlFor="promo-code-input" className="block text-xs uppercase tracking-wide text-white/60">
                        Cod reducere
                      </label>
                      <p className="text-sm text-white/70">Ai un voucher? Introdu-l mai jos și aplică reducerea instant.</p>
                      {appliedPromo && (
                        <p className="text-sm text-emerald-200">
                          Cod activ · <span className="font-semibold">{appliedPromo.code}</span>
                        </p>
                      )}
                    </div>

                    <div className="space-y-3">
                      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                        <input
                          id="promo-code-input"
                          type="text"
                          value={promoCode}
                          onChange={(e) => setPromoCode(e.target.value.toUpperCase())}
                          className="input uppercase tracking-[0.25em] text-sm font-semibold"
                          placeholder="EX: REDUCERE10"
                        />
                        <button
                          type="button"
                          onClick={handleApplyPromo}
                          className="btn-primary w-full sm:w-auto disabled:opacity-60 disabled:cursor-not-allowed"
                          disabled={promoLoading}
                        >
                          {promoLoading ? 'Se verifică…' : 'Aplică codul'}
                        </button>
                      </div>

                      {appliedPromo && (
                        <div className="flex flex-col gap-2 rounded-xl bg-emerald-500/10 px-4 py-3 text-sm text-emerald-100 sm:flex-row sm:items-center sm:justify-between">
                          <span>
                            Reducere aplicată: -{formatPrice(discountAmount, trip.currency)}
                          </span>
                          <button
                            type="button"
                            onClick={handleRemovePromo}
                            className="inline-flex items-center gap-1 text-emerald-200 hover:text-emerald-100"
                          >
                            Elimină codul
                          </button>
                        </div>
                      )}

                      {promoFeedback && (
                        <p className="text-sm text-white/70">{promoFeedback}</p>
                      )}
                    </div>
                  </div>

                  <div className="grid md:grid-cols-2 gap-4 text-sm">
                    <div className="space-y-1">
                      <div className="text-white/60">Subtotal</div>
                      <div className="font-semibold">
                        {subtotal > 0 ? formatPrice(subtotal, trip.currency) : '0'}
                      </div>
                    </div>
                    <div className="space-y-1 md:text-right">
                      <div className="text-white/60">Reducere</div>
                      <div className="font-semibold text-emerald-300">
                        {discountAmount > 0 ? `-${formatPrice(discountAmount, trip.currency)}` : '0'}
                      </div>
                    </div>
                    <div className="space-y-1 md:text-right md:col-span-2">
                      <div className="text-white/70 uppercase text-xs tracking-wide">Total de plată</div>
                      <div className="text-2xl font-extrabold">
                        {totalDue > 0 ? formatPrice(totalDue, trip.currency) : '0'}
                      </div>
                    </div>
                  </div>

                  <div className="grid md:grid-cols-2 gap-4">
                    <div>
                      <label className="block text-xs uppercase tracking-wide text-white/60 mb-2">Nume complet</label>
                      <input
                        type="text"
                        value={contact.name}
                        onChange={(e) => setContact((prev) => ({ ...prev, name: e.target.value }))}
                        className="input"
                        placeholder="Introduceți numele"
                      />
                    </div>
                    <div>
                      <label className="block text-xs uppercase tracking-wide text-white/60 mb-2">Telefon</label>
                      <input
                        type="tel"
                        value={contact.phone}
                        onChange={(e) => setContact((prev) => ({ ...prev, phone: e.target.value }))}
                        className="input"
                        placeholder="07xxxxxxxx"
                      />
                    </div>
                  </div>

                  {submitError && (
                    <div className="text-sm text-rose-400">{submitError}</div>
                  )}

                  <button
                    className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed"
                    disabled={submitting || !selectedSeats.length}
                    onClick={handleSubmit}
                  >
                    {submitting ? 'Se procesează…' : 'Continuă la rezervare 🔒'}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <div className="flex items-center gap-3">
      <span className={`inline-block size-6 rounded-md ${color}`} />
      <span className="text-white/80">{label}</span>
    </div>
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

function formatPrice(value: number, currency: string | null) {
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
