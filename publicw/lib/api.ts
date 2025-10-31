export class ApiError extends Error {
  status: number;
  payload: unknown;

  constructor(message: string, status: number, payload: unknown) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.payload = payload;
  }
}

const API_BASE = (process.env.NEXT_PUBLIC_BACKEND_URL || 'http://localhost:5000').replace(/\/$/, '');

type RequestOptions = RequestInit & { parseJson?: boolean };

async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const url = `${API_BASE}${path.startsWith('/') ? path : `/${path}`}`;
  const { parseJson = true, headers, ...rest } = options;
  const response = await fetch(url, {
    ...rest,
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      ...(headers || {}),
    },
  });

  let payload: any = null;
  if (parseJson) {
    const text = await response.text();
    if (text) {
      try {
        payload = JSON.parse(text);
      } catch {
        payload = text;
      }
    }
  }

  if (!response.ok) {
    const message = payload?.error || `A apărut o eroare (HTTP ${response.status}).`;
    throw new ApiError(message, response.status, payload);
  }

  return (payload ?? null) as T;
}

export interface StationOption {
  id: number;
  name: string;
}

export interface StationRelation {
  from_station_id: number;
  to_station_id: number;
}

export interface RouteSummary {
  id: number;
  name: string;
  stations: string[];
}

export interface RoutesMeta {
  stations: StationOption[];
  relations: StationRelation[];
  routes: RouteSummary[];
}

export interface PublicTrip {
  trip_id: number;
  route_id: number;
  route_name: string;
  direction: 'tur' | 'retur';
  departure_time: string;
  arrival_time: string | null;
  duration_minutes: number | null;
  price: number | null;
  currency: string | null;
  price_list_id: number | null;
  pricing_category_id: number | null;
  available_seats: number | null;
  can_book: boolean;
  board_station_id: number;
  exit_station_id: number;
  date: string;
  schedule_id: number | null;
}

export interface SeatInfo {
  id: number;
  label: string;
  row: number;
  seat_col: number;
  seat_type: string;
  status: 'free' | 'partial' | 'full';
  is_available: boolean;
  hold_status?: 'mine' | 'other' | null;
}

export interface SeatVehicle {
  vehicle_id: number;
  vehicle_name: string;
  plate_number: string | null;
  is_primary: boolean;
  seats: SeatInfo[];
}

export interface SeatMapResponse {
  trip_id: number;
  board_station_id: number;
  exit_station_id: number;
  available_seats: number | null;
  vehicles: SeatVehicle[];
}

export interface IntentInfo {
  seat_id: number;
  expires_at: string | null;
  is_mine: 0 | 1;
}

export interface SearchTripsParams {
  fromStationId: number;
  toStationId: number;
  date: string;
  passengers?: number;
}

export interface CreateReservationPayload {
  trip_id: number;
  board_station_id: number;
  exit_station_id: number;
  seats: number[];
  contact: {
    name: string;
    phone: string;
  };
  note?: string;
  promo?: PromoApplyPayload | null;
}

export interface CreateReservationResponse {
  success: boolean;
  reservation_ids: number[];
  trip_id: number;
  amount_total: number | null;
  discount_total?: number | null;
  currency: string | null;
}

export interface PromoValidationPayload {
  code: string;
  trip_id: number;
  board_station_id: number;
  exit_station_id: number;
  seat_count: number;
  phone?: string;
}

export interface PromoValidationResponse {
  valid: boolean;
  reason?: string;
  promo_code_id?: number;
  code?: string;
  type?: string;
  value_off?: number;
  discount_amount?: number;
  combinable?: boolean;
}

export interface PromoApplyPayload {
  code: string;
  promo_code_id: number;
  discount_amount: number;
  value_off: number;
}

export async function fetchRoutesMeta(): Promise<RoutesMeta> {
  return request<RoutesMeta>('/api/public/routes');
}

export async function searchPublicTrips(params: SearchTripsParams): Promise<PublicTrip[]> {
  const query = new URLSearchParams({
    from_station_id: String(params.fromStationId),
    to_station_id: String(params.toStationId),
    date: params.date,
  });
  if (params.passengers) {
    query.set('passengers', String(params.passengers));
  }
  return request<PublicTrip[]>(`/api/public/trips?${query.toString()}`);
}

export async function fetchTripSeatMap(tripId: number, boardStationId: number, exitStationId: number): Promise<SeatMapResponse> {
  const query = new URLSearchParams({
    board_station_id: String(boardStationId),
    exit_station_id: String(exitStationId),
  });
  return request<SeatMapResponse>(`/api/public/trips/${tripId}/seats?${query.toString()}`);
}

export async function createPublicReservation(payload: CreateReservationPayload): Promise<CreateReservationResponse> {
  return request<CreateReservationResponse>('/api/public/reservations', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function fetchTripIntents(tripId: number): Promise<IntentInfo[]> {
  return request<IntentInfo[]>(`/api/intents?trip_id=${tripId}`);
}

export async function createIntent(payload: { trip_id: number; seat_id: number }): Promise<void> {
  await request('/api/intents', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function deleteIntent(tripId: number, seatId: number): Promise<void> {
  await request(`/api/intents/${tripId}/${seatId}`, {
    method: 'DELETE',
  });
}

export async function validatePromoCode(payload: PromoValidationPayload): Promise<PromoValidationResponse> {
  return request<PromoValidationResponse>('/api/public/promo/validate', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}
