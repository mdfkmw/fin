const express = require('express');
const router = express.Router();
const db = require('../db');
const { normalizeDirection, isReturnDirection } = require('../utils/direction');
const { ensureIntentOwner } = require('../utils/intentOwner');

const PUBLIC_CATEGORY_CANDIDATES = (() => {
  const raw = process.env.PUBLIC_PRICING_CATEGORY_IDS || '2,1';
  const parts = raw
    .split(',')
    .map((p) => Number(p.trim()))
    .filter((n) => Number.isFinite(n) && n > 0);
  if (parts.length === 0) return [1];
  const seen = new Set();
  const ordered = [];
  for (const id of parts) {
    if (seen.has(id)) continue;
    seen.add(id);
    ordered.push(id);
  }
  return ordered;
})();

// Exclusiv categoria Online pentru public (fără fallback)
const PUBLIC_ONLY_CATEGORY_ID = Number(process.env.PUBLIC_ONLY_CATEGORY_ID || 2);


async function execQuery(client, sql, params = []) {
  if (client && typeof client.query === 'function' && client !== db) {
    const [rows] = await client.query(sql, params);
    const isArray = Array.isArray(rows);
    const insertId = typeof rows?.insertId === 'number' ? rows.insertId : null;
    return {
      rows: isArray ? rows : [],
      insertId,
      raw: rows,
    };
  }
  return db.query(sql, params);
}

function sanitizeDate(dateStr) {
  if (!dateStr) return null;
  const str = String(dateStr).slice(0, 10);
  if (!/\d{4}-\d{2}-\d{2}/.test(str)) return null;
  return str;
}

function sanitizePhone(raw) {
  if (!raw) return '';
  return String(raw).replace(/\D/g, '').slice(0, 20);
}

function toHHMM(timeStr) {
  if (!timeStr) return null;
  const str = String(timeStr);
  if (str.length >= 5) return str.slice(0, 5);
  if (/^\d{1,2}:\d{1,2}$/.test(str)) return str;
  return null;
}

function addMinutesToTime(timeStr, minutes) {
  if (!timeStr || !Number.isFinite(minutes)) return null;
  const parts = String(timeStr).split(':');
  if (parts.length < 2) return null;
  const hours = Number(parts[0]);
  const mins = Number(parts[1]);
  if (!Number.isFinite(hours) || !Number.isFinite(mins)) return null;
  const base = Date.UTC(1970, 0, 1, hours, mins, 0);
  const result = new Date(base + minutes * 60000);
  const hh = String(result.getUTCHours()).padStart(2, '0');
  const mm = String(result.getUTCMinutes()).padStart(2, '0');
  return `${hh}:${mm}`;
}

async function estimateSegmentDuration(client, routeId, direction, boardStationId, exitStationId) {
  const { rows } = await execQuery(
    client,
    `
    SELECT station_id, travel_time_from_previous_minutes
      FROM route_stations
     WHERE route_id = ?
     ORDER BY sequence ASC
    `,
    [routeId]
  );

  if (!rows.length) return null;

  const stationIds = rows.map((row) => Number(row.station_id));
  const travel = rows.map((row, idx) => {
    if (idx === 0) return 0;
    const val = Number(row.travel_time_from_previous_minutes);
    return Number.isFinite(val) ? val : 0;
  });

  if (!stationIds.includes(Number(boardStationId)) || !stationIds.includes(Number(exitStationId))) {
    return null;
  }

  let orderIds = stationIds.slice();
  let travelFromPrev = travel.slice();

  if (isReturnDirection(direction)) {
    orderIds = stationIds.slice().reverse();
    travelFromPrev = orderIds.map((_, idx) => {
      if (idx === 0) return 0;
      const sourceIndex = stationIds.length - idx;
      return Number.isFinite(travel[sourceIndex]) ? travel[sourceIndex] : 0;
    });
  }

  let total = 0;
  let started = false;
  for (let i = 0; i < orderIds.length; i += 1) {
    const stationId = orderIds[i];
    if (!started) {
      if (stationId === Number(boardStationId)) {
        started = true;
      }
      continue;
    }
    total += Number.isFinite(travelFromPrev[i]) ? travelFromPrev[i] : 0;
    if (stationId === Number(exitStationId)) {
      return { minutes: total };
    }
  }

  return null;
}

async function getAllowedCategories(client, scheduleId) {
  if (!scheduleId) return null;
  const { rows } = await execQuery(
    client,
    `SELECT pricing_category_id FROM route_schedule_pricing_categories WHERE route_schedule_id = ?`,
    [scheduleId]
  );
  if (!rows.length) return null;
  return rows.map((row) => Number(row.pricing_category_id)).filter((n) => Number.isFinite(n));
}

async function getPublicPrice(client, { routeId, fromStationId, toStationId, date, scheduleId }) {
  if (!routeId || !fromStationId || !toStationId || !date) return null;
  // PUBLIC: ignorăm whitelisting-ul pe orar; afișăm EXCLUSIV categoria Online
  const catId = PUBLIC_ONLY_CATEGORY_ID;

  const { rows } = await execQuery(
    client,
    `
      SELECT
        pli.price,
        pl.id          AS price_list_id,
        pl.category_id AS pricing_category_id
      FROM price_list_items pli
      JOIN price_lists      pl ON pl.id = pli.price_list_id
      WHERE pl.route_id = ?
        AND pli.from_station_id = ?
        AND pli.to_station_id   = ?
        AND pl.category_id      = ?
        AND pl.effective_from = (
              SELECT MAX(effective_from)
                FROM price_lists
               WHERE route_id    = ?
                 AND category_id = ?
                 AND effective_from <= DATE(?)
        )
      LIMIT 1
    `,
    [routeId, fromStationId, toStationId, catId, routeId, catId, date]
  );

  if (!rows.length) return null; // FĂRĂ FALLBACK: dacă nu există Online, nu dăm altă categorie

  return {
    price: Number(rows[0].price),
    price_list_id: rows[0].price_list_id,
    pricing_category_id: rows[0].pricing_category_id,
  };
}

async function validatePromoForTrip(client, {
  code,
  tripId,
  boardStationId,
  exitStationId,
  seatCount,
  phone,
  priceInfoOverride = null,
}) {
  const cleanCode = String(code || '').trim().toUpperCase();
  if (!cleanCode) {
    return { valid: false, reason: 'Cod lipsă' };
  }

  const seats = Number(seatCount || 0);
  if (!Number.isFinite(seats) || seats <= 0) {
    return { valid: false, reason: 'Selectează locurile înainte de a aplica codul.' };
  }

  const trip = await loadTripBasics(client, tripId);
  if (!trip) {
    return { valid: false, reason: 'Cursa nu mai este disponibilă.' };
  }

  const travelDate = sanitizeDate(trip.date);
  if (!travelDate) {
    return { valid: false, reason: 'Data cursei nu a putut fi validată.' };
  }

  let priceInfo = priceInfoOverride;
  if (!priceInfo) {
    priceInfo = await getPublicPrice(client, {
      routeId: trip.route_id,
      fromStationId: boardStationId,
      toStationId: exitStationId,
      date: travelDate,
      scheduleId: trip.schedule_id,
    });
  }

  if (!priceInfo || !Number.isFinite(Number(priceInfo.price))) {
    return { valid: false, reason: 'Tariful pentru această rută nu este disponibil.' };
  }

  const perSeatPrice = Number(priceInfo.price);
  const baseAmount = +(perSeatPrice * seats).toFixed(2);
  if (baseAmount <= 0) {
    return { valid: false, reason: 'Valoarea comenzii este zero.' };
  }

  const promoRes = await execQuery(
    client,
    `SELECT * FROM promo_codes
       WHERE UPPER(code)=? AND active=1
         AND (valid_from IS NULL OR NOW() >= valid_from)
         AND (valid_to   IS NULL OR NOW() <= valid_to)
      LIMIT 1`,
    [cleanCode]
  );

  const promo = promoRes.rows?.[0];
  if (!promo) {
    return { valid: false, reason: 'Cod inexistent sau expirat.' };
  }

  const channels = (promo.channels || '').split(',');
  if (!channels.includes('online')) {
    return { valid: false, reason: 'Codul nu este disponibil online.' };
  }

  const routesCount = await execQuery(
    client,
    'SELECT COUNT(*) AS c FROM promo_code_routes WHERE promo_code_id = ?',
    [promo.id]
  );
  if ((routesCount.rows?.[0]?.c ?? 0) > 0) {
    const allowed = await execQuery(
      client,
      'SELECT COUNT(*) AS c FROM promo_code_routes WHERE promo_code_id=? AND route_id=?',
      [promo.id, trip.route_id]
    );
    if (!((allowed.rows?.[0]?.c ?? 0) > 0)) {
      return { valid: false, reason: 'Cod indisponibil pentru această rută.' };
    }
  }

  const schedulesCount = await execQuery(
    client,
    'SELECT COUNT(*) AS c FROM promo_code_schedules WHERE promo_code_id=?',
    [promo.id]
  );
  if ((schedulesCount.rows?.[0]?.c ?? 0) > 0) {
    const allowed = await execQuery(
      client,
      'SELECT COUNT(*) AS c FROM promo_code_schedules WHERE promo_code_id=? AND route_schedule_id=?',
      [promo.id, trip.schedule_id || 0]
    );
    if (!((allowed.rows?.[0]?.c ?? 0) > 0)) {
      return { valid: false, reason: 'Codul nu este valabil pentru această plecare.' };
    }
  }

  const hhmm = toHHMM(trip.departure_time || trip.time);
  const hoursCount = await execQuery(
    client,
    'SELECT COUNT(*) AS c FROM promo_code_hours WHERE promo_code_id=?',
    [promo.id]
  );
  if ((hoursCount.rows?.[0]?.c ?? 0) > 0) {
    const within = await execQuery(
      client,
      'SELECT COUNT(*) AS c FROM promo_code_hours WHERE promo_code_id=? AND ? BETWEEN start_time AND end_time',
      [promo.id, hhmm || '']
    );
    if (!((within.rows?.[0]?.c ?? 0) > 0)) {
      return { valid: false, reason: 'Codul nu este disponibil la această oră.' };
    }
  }

  const weekday = Number.isFinite(new Date(travelDate).getTime())
    ? new Date(travelDate).getDay()
    : null;
  const weekdayCount = await execQuery(
    client,
    'SELECT COUNT(*) AS c FROM promo_code_weekdays WHERE promo_code_id=?',
    [promo.id]
  );
  if ((weekdayCount.rows?.[0]?.c ?? 0) > 0) {
    const allowed = await execQuery(
      client,
      'SELECT COUNT(*) AS c FROM promo_code_weekdays WHERE promo_code_id=? AND weekday=?',
      [promo.id, weekday]
    );
    if (!((allowed.rows?.[0]?.c ?? 0) > 0)) {
      return { valid: false, reason: 'Codul nu este valabil în această zi.' };
    }
  }

  const totalUses = await execQuery(
    client,
    'SELECT COUNT(*) AS c FROM promo_code_usages WHERE promo_code_id=?',
    [promo.id]
  );
  if (promo.max_total_uses && (totalUses.rows?.[0]?.c ?? 0) >= promo.max_total_uses) {
    return { valid: false, reason: 'S-a atins numărul maxim de utilizări.' };
  }

  const cleanPhone = sanitizePhone(phone);
  if (cleanPhone) {
    const perPerson = await execQuery(
      client,
      'SELECT COUNT(*) AS c FROM promo_code_usages WHERE promo_code_id=? AND phone=?',
      [promo.id, cleanPhone]
    );
    if (promo.max_uses_per_person && (perPerson.rows?.[0]?.c ?? 0) >= promo.max_uses_per_person) {
      return { valid: false, reason: 'Acest cod a fost deja folosit pentru numărul introdus.' };
    }
  }

  if (promo.min_price && baseAmount < Number(promo.min_price)) {
    return { valid: false, reason: 'Valoarea minimă pentru cod nu este atinsă.' };
  }

  let discount = promo.type === 'percent'
    ? +(baseAmount * (Number(promo.value_off) / 100)).toFixed(2)
    : +Number(promo.value_off);

  if (promo.max_discount) {
    discount = Math.min(discount, Number(promo.max_discount));
  }
  discount = Math.min(discount, baseAmount);

  if (!Number.isFinite(discount) || discount <= 0) {
    return { valid: false, reason: 'Reducere indisponibilă pentru selecția curentă.' };
  }

  return {
    valid: true,
    promo_code_id: promo.id,
    code: cleanCode,
    type: promo.type,
    value_off: Number(promo.value_off),
    discount_amount: Number(discount),
    combinable: !!promo.combinable,
    base_amount: baseAmount,
    price_per_seat: perSeatPrice,
  };
}


async function loadTripBasics(client, tripId) {
  const { rows } = await execQuery(
    client,
    `
    SELECT
      t.id,
      t.route_id,
      t.vehicle_id,
      t.date,
      DATE_FORMAT(t.time, '%H:%i') AS departure_time,
      t.time,
      rs.direction,
      rs.id AS schedule_id
    FROM trips t
    JOIN route_schedules rs ON rs.id = t.route_schedule_id
    WHERE t.id = ?
      AND NOT EXISTS (
        SELECT 1
          FROM schedule_exceptions se
         WHERE se.schedule_id = t.route_schedule_id
           AND se.disable_online = 1
           AND (
                 se.exception_date IS NULL
              OR se.exception_date = DATE(t.date)
              OR (se.weekday IS NOT NULL AND se.weekday = DAYOFWEEK(t.date) - 1)
           )
      )
    LIMIT 1
    `,
    [tripId]
  );
  return rows[0] || null;
}

async function loadTripStationSequences(client, tripId) {
  const { rows } = await execQuery(
    client,
    `SELECT station_id, sequence FROM trip_stations WHERE trip_id = ?`,
    [tripId]
  );
  const map = new Map();
  rows.forEach((row) => {
    map.set(Number(row.station_id), Number(row.sequence));
  });
  return map;
}

async function computeSeatAvailability(client, {
  tripId,
  boardStationId,
  exitStationId,
  includeSeats = true,
  intentOwnerId = null,
}) {
  const trip = await loadTripBasics(client, tripId);
  if (!trip) return null;

  const stationSeq = await loadTripStationSequences(client, tripId);
  const boardSeq = stationSeq.get(Number(boardStationId));
  const exitSeq = stationSeq.get(Number(exitStationId));
  if (!Number.isFinite(boardSeq) || !Number.isFinite(exitSeq) || boardSeq >= exitSeq) {
    return null;
  }

  const normalizedOwner = Number.isInteger(intentOwnerId) ? Number(intentOwnerId) : null;

  const { rows: intentRows } = await execQuery(
    client,
    `
      SELECT seat_id, user_id
        FROM reservation_intents
       WHERE trip_id = ?
         AND expires_at > NOW()
    `,
    [tripId],
  );

  const intentBySeat = new Map();
  for (const row of intentRows) {
    const seatId = Number(row.seat_id);
    if (!Number.isFinite(seatId)) continue;
    const ownerId = row.user_id === null ? null : Number(row.user_id);
    intentBySeat.set(seatId, Number.isFinite(ownerId) ? ownerId : null);
  }

  const vehicles = [];
  const seenVehicleIds = new Set();

  if (trip.vehicle_id) {
    const { rows } = await execQuery(
      client,
      `SELECT id, name, plate_number FROM vehicles WHERE id = ? LIMIT 1`,
      [trip.vehicle_id]
    );
    if (rows.length) {
      vehicles.push({
        vehicle_id: rows[0].id,
        vehicle_name: rows[0].name,
        plate_number: rows[0].plate_number,
        is_primary: true,
      });
      seenVehicleIds.add(rows[0].id);
    }
  }

  const { rows: tvRows } = await execQuery(
    client,
    `
    SELECT v.id, v.name, v.plate_number, tv.is_primary
      FROM trip_vehicles tv
      JOIN vehicles v ON v.id = tv.vehicle_id
     WHERE tv.trip_id = ?
     ORDER BY tv.is_primary DESC, v.id
    `,
    [tripId]
  );

  for (const row of tvRows) {
    if (seenVehicleIds.has(row.id)) {
      const idx = vehicles.findIndex((v) => v.vehicle_id === row.id);
      if (idx !== -1 && row.is_primary && !vehicles[idx].is_primary) {
        vehicles[idx].is_primary = true;
      }
      continue;
    }
    vehicles.push({
      vehicle_id: row.id,
      vehicle_name: row.name,
      plate_number: row.plate_number,
      is_primary: !!row.is_primary,
    });
    seenVehicleIds.add(row.id);
  }

  if (vehicles.length === 0) return null;

  let totalAvailable = 0;

  for (const veh of vehicles) {
    const { rows: seatRows } = await execQuery(
      client,
      `
      SELECT id, label, row, seat_col, seat_type, seat_number
        FROM seats
       WHERE vehicle_id = ?
       ORDER BY row, seat_col, id
      `,
      [veh.vehicle_id]
    );

    const { rows: resRows } = await execQuery(
      client,
      `
      SELECT r.seat_id, r.board_station_id, r.exit_station_id, r.status
        FROM reservations r
        JOIN seats s ON s.id = r.seat_id
       WHERE r.trip_id = ?
         AND r.status <> 'cancelled'
         AND s.vehicle_id = ?
      `,
      [tripId, veh.vehicle_id]
    );

    const seatReservations = new Map();
    for (const r of resRows) {
      const seatId = Number(r.seat_id);
      if (!seatReservations.has(seatId)) seatReservations.set(seatId, []);
      seatReservations.get(seatId).push({
        board: stationSeq.get(Number(r.board_station_id)),
        exit: stationSeq.get(Number(r.exit_station_id)),
        status: r.status,
      });
    }

    const seatList = [];

    for (const seat of seatRows) {
      const passengers = seatReservations.get(Number(seat.id)) || [];
      let isAvailable = true;
      let status = 'free';
      const overlaps = [];

      const seatId = Number(seat.id);
      const holdOwnerId = intentBySeat.get(seatId);
      const heldByMe = holdOwnerId !== undefined && holdOwnerId !== null && holdOwnerId === normalizedOwner;
      const heldByOther = holdOwnerId === null
        ? true
        : holdOwnerId !== undefined && holdOwnerId !== normalizedOwner;

      for (const p of passengers) {
        if (p.status !== 'active') continue;
        const rBoard = p.board;
        const rExit = p.exit;
        if (!Number.isFinite(rBoard) || !Number.isFinite(rExit)) continue;
        const overlap = Math.max(boardSeq, rBoard) < Math.min(exitSeq, rExit);
        if (overlap) {
          isAvailable = false;
          status = 'partial';
          overlaps.push({
            start: Math.max(boardSeq, rBoard),
            end: Math.min(exitSeq, rExit),
          });
          if (rBoard <= boardSeq && rExit >= exitSeq) {
            status = 'full';
            break;
          }
        }
      }

      if (!isAvailable && status === 'partial' && overlaps.length) {
        overlaps.sort((a, b) => (a.start - b.start) || (b.end - a.end));
        let coverage = boardSeq;
        let hasGap = false;
        for (const seg of overlaps) {
          if (seg.start > coverage) {
            hasGap = true;
            break;
          }
          coverage = Math.max(coverage, seg.end);
          if (coverage >= exitSeq) break;
        }
        if (!hasGap && coverage >= exitSeq) {
          status = 'full';
        }
      }

      if (heldByOther) {
        isAvailable = false;
        if (status === 'free') status = 'partial';
      }

      const selectable = isAvailable && !heldByOther;
      const countsAsAvailable = selectable && !heldByMe;

      if (seat.seat_type !== 'driver' && seat.seat_type !== 'guide' && countsAsAvailable) {
        totalAvailable += 1;
      }

      if (includeSeats) {
        seatList.push({
          id: seat.id,
          label: seat.label,
          row: seat.row,
          seat_col: seat.seat_col,
          seat_type: seat.seat_type,
          seat_number: seat.seat_number,
          status,
          is_available: selectable,
          hold_status: heldByMe ? 'mine' : heldByOther ? 'other' : null,
        });
      }
    }

    if (includeSeats) {
      veh.seats = seatList;
    }
  }

  return {
    trip,
    vehicles,
    totalAvailable,
  };
}

router.get('/routes', async (_req, res) => {
  try {
    const { rows } = await db.query(
      `
      SELECT
        rs.route_id,
        r.name AS route_name,
        rs.station_id,
        rs.sequence,
        s.name AS station_name
      FROM route_stations rs
      JOIN routes r ON r.id = rs.route_id
      JOIN stations s ON s.id = rs.station_id
      WHERE r.visible_online = 1
      ORDER BY rs.route_id, rs.sequence
      `
    );

    if (!rows.length) {
      return res.json({ stations: [], relations: [] });
    }

    const stationsMap = new Map();
    const byRoute = new Map();

    for (const row of rows) {
      stationsMap.set(Number(row.station_id), row.station_name);
      const routeId = Number(row.route_id);
      if (!byRoute.has(routeId)) {
        byRoute.set(routeId, { name: row.route_name, stationIds: [] });
      }
      const entry = byRoute.get(routeId);
      entry.stationIds.push(Number(row.station_id));
    }

    const relationSet = new Set();
    for (const routeInfo of byRoute.values()) {
      const stationList = routeInfo.stationIds;
      for (let i = 0; i < stationList.length; i += 1) {
        for (let j = i + 1; j < stationList.length; j += 1) {
          const from = stationList[i];
          const to = stationList[j];
          relationSet.add(`${from}|${to}`);
          relationSet.add(`${to}|${from}`);
        }
      }
    }

    const stations = Array.from(stationsMap.entries())
      .map(([id, name]) => ({ id: Number(id), name }))
      .sort((a, b) => a.name.localeCompare(b.name));

    const relations = Array.from(relationSet).map((key) => {
      const [from, to] = key.split('|').map((n) => Number(n));
      return { from_station_id: from, to_station_id: to };
    });

    const routes = Array.from(byRoute.entries())
      .map(([id, info]) => ({
        id: Number(id),
        name: info.name,
        stations: info.stationIds
          .map((stationId) => stationsMap.get(stationId))
          .filter(Boolean),
      }))
      .sort((a, b) => a.name.localeCompare(b.name));

    res.json({ stations, relations, routes });
  } catch (err) {
    console.error('[public/routes] error', err);
    res.status(500).json({ error: 'Eroare internă la încărcarea stațiilor.' });
  }
});

router.get('/trips', async (req, res) => {
  const fromStationId = Number(req.query.from_station_id);
  const toStationId = Number(req.query.to_station_id);
  const date = sanitizeDate(req.query.date);
  const passengers = Number(req.query.passengers || 1) || 1;
  const { ownerId: intentOwnerId } = ensureIntentOwner(req, res);

  if (!fromStationId || !toStationId || !date) {
    return res.status(400).json({ error: 'Parametri incompleți pentru căutare.' });
  }

  try {
    const { rows } = await db.query(
      `
      SELECT
        t.id AS trip_id,
        t.route_id,
        DATE_FORMAT(t.time, '%H:%i') AS departure_time,
        rs.direction,
        rs.id AS schedule_id,
        r.name AS route_name
      FROM trips t
      JOIN trip_stations board ON board.trip_id = t.id AND board.station_id = ?
      JOIN trip_stations \`exit\` ON \`exit\`.trip_id = t.id AND \`exit\`.station_id = ?
      JOIN route_schedules rs ON rs.id = t.route_schedule_id
      JOIN routes r ON r.id = t.route_id
      WHERE t.date = DATE(?)
        AND board.sequence < \`exit\`.sequence
        AND r.visible_online = 1
        AND NOT EXISTS (
          SELECT 1
            FROM schedule_exceptions se
           WHERE se.schedule_id = t.route_schedule_id
             AND se.disable_online = 1
             AND (
                  se.exception_date IS NULL
               OR se.exception_date = DATE(?)
               OR (se.weekday IS NOT NULL AND se.weekday = DAYOFWEEK(DATE(?)) - 1)
             )
        )
      ORDER BY t.time ASC
      `,
      [fromStationId, toStationId, date, date, date]
    );

    const results = [];
    for (const trip of rows) {
      const seatInfo = await computeSeatAvailability(db, {
        tripId: trip.trip_id,
        boardStationId: fromStationId,
        exitStationId: toStationId,
        includeSeats: false,
        intentOwnerId,
      });

      if (!seatInfo) continue;

      const durationInfo = await estimateSegmentDuration(
        db,
        trip.route_id,
        trip.direction,
        fromStationId,
        toStationId
      );

      const priceInfo = await getPublicPrice(db, {
        routeId: trip.route_id,
        fromStationId,
        toStationId,
        date,
        scheduleId: trip.schedule_id,
      });

      const available = Number.isFinite(seatInfo.totalAvailable) ? seatInfo.totalAvailable : null;
      const canBook = available == null ? true : available >= Math.max(passengers, 1);

      results.push({
        trip_id: trip.trip_id,
        route_id: trip.route_id,
        route_name: trip.route_name,
        direction: normalizeDirection(trip.direction),
        departure_time: trip.departure_time,
        arrival_time: durationInfo?.minutes ? addMinutesToTime(trip.departure_time, durationInfo.minutes) : null,
        duration_minutes: durationInfo?.minutes ?? null,
        price: priceInfo?.price ?? null,
        currency: priceInfo ? 'RON' : null,
        price_list_id: priceInfo?.price_list_id ?? null,
        pricing_category_id: priceInfo?.pricing_category_id ?? null,
        available_seats: available,
        can_book: canBook,
        board_station_id: fromStationId,
        exit_station_id: toStationId,
        date,
        schedule_id: trip.schedule_id,
      });
    }

    res.json(results);
  } catch (err) {
    console.error('[public/trips] error', err);
    res.status(500).json({ error: 'Eroare internă la căutarea curselor.' });
  }
});

router.get('/trips/:tripId/seats', async (req, res) => {
  const tripId = Number(req.params.tripId);
  const boardStationId = Number(req.query.board_station_id);
  const exitStationId = Number(req.query.exit_station_id);

  if (!tripId || !boardStationId || !exitStationId) {
    return res.status(400).json({ error: 'Parametri insuficienți pentru diagrama locurilor.' });
  }

  try {
    const { ownerId: intentOwnerId } = ensureIntentOwner(req, res);
    const seatInfo = await computeSeatAvailability(db, {
      tripId,
      boardStationId,
      exitStationId,
      includeSeats: true,
      intentOwnerId,
    });

    if (!seatInfo) {
      return res.status(404).json({ error: 'Nu am găsit diagrama pentru cursa selectată.' });
    }

    const payload = {
      trip_id: tripId,
      board_station_id: boardStationId,
      exit_station_id: exitStationId,
      available_seats: seatInfo.totalAvailable,
        vehicles: seatInfo.vehicles.map((veh) => ({
          vehicle_id: veh.vehicle_id,
          vehicle_name: veh.vehicle_name,
          plate_number: veh.plate_number,
          is_primary: !!veh.is_primary,
          seats: (veh.seats || []).map((seat) => ({
            id: seat.id,
            label: seat.label,
            row: seat.row,
            seat_col: seat.seat_col,
            seat_type: seat.seat_type,
            status: seat.status,
            is_available: seat.is_available,
            hold_status: seat.hold_status ?? null,
          })),
        })),
      };

    res.json(payload);
  } catch (err) {
    console.error('[public/trip seats] error', err);
    res.status(500).json({ error: 'Eroare internă la încărcarea locurilor.' });
  }
});

async function findOrCreatePerson(conn, { name, phone }) {
  const cleanPhone = sanitizePhone(phone);
  const cleanName = name && String(name).trim() ? String(name).trim().slice(0, 255) : null;

  if (cleanPhone) {
    const { rows: existing } = await execQuery(
      conn,
      `SELECT id, name FROM people WHERE phone = ? LIMIT 1`,
      [cleanPhone]
    );
    if (existing.length) {
      const personId = existing[0].id;
      if (cleanName && (!existing[0].name || existing[0].name.trim() !== cleanName)) {
        await execQuery(conn, `UPDATE people SET name = ? WHERE id = ?`, [cleanName, personId]);
      }
      return personId;
    }
    const insert = await execQuery(
      conn,
      `INSERT INTO people (name, phone) VALUES (?, ?)`,
      [cleanName, cleanPhone]
    );
    if (Number.isFinite(insert.insertId)) return insert.insertId;
    if (Number.isFinite(insert.raw?.insertId)) return insert.raw.insertId;
    return null;
  }

  if (cleanName) {
    const { rows: sameName } = await execQuery(
      conn,
      `SELECT id FROM people WHERE name = ? AND phone IS NULL LIMIT 1`,
      [cleanName]
    );
    if (sameName.length) return sameName[0].id;
    const insert = await execQuery(
      conn,
      `INSERT INTO people (name, phone) VALUES (?, NULL)`,
      [cleanName]
    );
    if (Number.isFinite(insert.insertId)) return insert.insertId;
    if (Number.isFinite(insert.raw?.insertId)) return insert.raw.insertId;
    return null;
  }

  return null;
}

async function isSeatFree(conn, { tripId, seatId, boardStationId, exitStationId }) {
  const [procRows] = await conn.query('CALL sp_is_seat_free(?, ?, ?, ?)', [
    tripId,
    seatId,
    boardStationId,
    exitStationId,
  ]);

  let resultRows = procRows;
  if (Array.isArray(procRows) && Array.isArray(procRows[0])) {
    resultRows = procRows[0];
  } else if (procRows && typeof procRows.rows === 'object') {
    resultRows = Array.isArray(procRows.rows[0]) ? procRows.rows[0] : procRows.rows;
  }

  const row = Array.isArray(resultRows) ? resultRows[0] : resultRows;
  const value = row && (row.is_free ?? row.IS_FREE ?? row.isFree ?? row[0]);
  return Number(value) === 1;
}

router.post('/promo/validate', async (req, res) => {
  try {
    const {
      code,
      trip_id: tripId,
      board_station_id: boardStationId,
      exit_station_id: exitStationId,
      seat_count: seatCount,
      phone,
    } = req.body || {};

    const validation = await validatePromoForTrip(null, {
      code,
      tripId: Number(tripId),
      boardStationId: Number(boardStationId),
      exitStationId: Number(exitStationId),
      seatCount,
      phone,
    });

    res.json(validation);
  } catch (err) {
    console.error('[public/promo/validate] error', err);
    res.status(500).json({ valid: false, reason: 'Nu am putut valida codul.' });
  }
});

router.post('/reservations', async (req, res) => {
  const {
    trip_id: tripIdRaw,
    board_station_id: boardStationIdRaw,
    exit_station_id: exitStationIdRaw,
    seats,
    contact,
    note,
    promo,
  } = req.body || {};

  const tripId = Number(tripIdRaw);
  const boardStationId = Number(boardStationIdRaw);
  const exitStationId = Number(exitStationIdRaw);
  const seatIds = Array.isArray(seats)
    ? seats.map((s) => Number(s)).filter((n) => Number.isFinite(n) && n > 0)
    : [];

  if (!tripId || !boardStationId || !exitStationId || seatIds.length === 0) {
    return res.status(400).json({ error: 'Date incomplete pentru rezervare.' });
  }

  const cleanName = contact?.name && String(contact.name).trim();
  const cleanPhone = sanitizePhone(contact?.phone);
  if (!cleanName || !cleanPhone) {
    return res.status(400).json({ error: 'Numele și telefonul sunt obligatorii.' });
  }

  const { ownerId: intentOwnerId } = ensureIntentOwner(req, res);

  const conn = await db.getConnection();
  try {
    await conn.beginTransaction();

    const trip = await loadTripBasics(conn, tripId);
    if (!trip) {
      await conn.rollback();
      conn.release();
      return res.status(404).json({ error: 'Cursa selectată nu există sau este indisponibilă.' });
    }

    const stationSeq = await loadTripStationSequences(conn, tripId);
    const boardSeq = stationSeq.get(Number(boardStationId));
    const exitSeq = stationSeq.get(Number(exitStationId));
    if (!Number.isFinite(boardSeq) || !Number.isFinite(exitSeq) || boardSeq >= exitSeq) {
      await conn.rollback();
      conn.release();
      return res.status(400).json({ error: 'Segment invalid pentru această cursă.' });
    }

    const vehicleIds = new Set();
    if (trip.vehicle_id) vehicleIds.add(Number(trip.vehicle_id));
    const { rows: otherVeh } = await execQuery(
      conn,
      `SELECT vehicle_id FROM trip_vehicles WHERE trip_id = ?`,
      [tripId]
    );
    for (const row of otherVeh) {
      vehicleIds.add(Number(row.vehicle_id));
    }

    if (vehicleIds.size === 0) {
      await conn.rollback();
      conn.release();
      return res.status(409).json({ error: 'Nu există vehicule asociate cursei.' });
    }

    const placeholders = seatIds.map(() => '?').join(',');
    const { rows: seatRows } = await execQuery(
      conn,
      `SELECT id, vehicle_id, seat_type FROM seats WHERE id IN (${placeholders})`,
      seatIds
    );

    if (seatRows.length !== seatIds.length) {
      await conn.rollback();
      conn.release();
      return res.status(400).json({ error: 'Cel puțin un loc selectat nu există.' });
    }

    for (const seat of seatRows) {
      if (!vehicleIds.has(Number(seat.vehicle_id))) {
        await conn.rollback();
        conn.release();
        return res.status(400).json({ error: 'Locul selectat nu aparține acestei curse.' });
      }
      const allowedTypes = new Set(['normal', 'foldable', 'wheelchair']);
      if (!allowedTypes.has(seat.seat_type)) {
        await conn.rollback();
        conn.release();
        return res.status(400).json({ error: 'Unele locuri nu sunt disponibile pentru pasageri.' });
      }
    }

    if (seatIds.length) {
      const { rows: intentRows } = await execQuery(
        conn,
        `SELECT seat_id, user_id FROM reservation_intents WHERE trip_id = ? AND seat_id IN (${placeholders}) AND expires_at > NOW()`,
        [tripId, ...seatIds],
      );

      const normalizedOwner = Number.isInteger(intentOwnerId) ? Number(intentOwnerId) : null;
      for (const intent of intentRows) {
        const owner = intent.user_id === null ? null : Number(intent.user_id);
        const sameOwner = normalizedOwner !== null && owner === normalizedOwner;
        if (!sameOwner) {
          await conn.rollback();
          conn.release();
          return res.status(409).json({ error: 'Unul dintre locuri este rezervat temporar de alt client.' });
        }
      }
    }

    for (const seatId of seatIds) {
      const free = await isSeatFree(conn, {
        tripId,
        seatId,
        boardStationId,
        exitStationId,
      });
      if (!free) {
        await conn.rollback();
        conn.release();
        return res.status(409).json({ error: 'Unul dintre locuri a fost rezervat între timp. Te rugăm să actualizezi.' });
      }
    }

    const personId = await findOrCreatePerson(conn, {
      name: cleanName,
      phone: cleanPhone,
    });

    const priceInfo = await getPublicPrice(conn, {
      routeId: trip.route_id,
      fromStationId: boardStationId,
      toStationId: exitStationId,
      date: sanitizeDate(trip.date),
      scheduleId: trip.schedule_id,
    });

    let promoResult = null;
    if (promo && promo.code) {
      promoResult = await validatePromoForTrip(conn, {
        code: promo.code,
        tripId,
        boardStationId,
        exitStationId,
        seatCount: seatIds.length,
        phone: cleanPhone,
        priceInfoOverride: priceInfo,
      });
      if (!promoResult.valid) {
        await conn.rollback();
        conn.release();
        return res.status(400).json({ error: promoResult.reason || 'Codul promoțional nu este valid.' });
      }
    }

    const reservationIds = [];
    const observation = note && String(note).trim() ? String(note).trim().slice(0, 500) : null;

    let promoRemaining = promoResult?.discount_amount ? Number(promoResult.discount_amount) : 0;

    for (const seatId of seatIds) {
      const insertRes = await execQuery(
        conn,
        `
        INSERT INTO reservations (trip_id, seat_id, person_id, board_station_id, exit_station_id, observations, created_by)
        VALUES (?, ?, ?, ?, ?, ?, NULL)
        `,
        [tripId, seatId, personId, boardStationId, exitStationId, observation || 'Rezervare online']
      );
      let reservationId = null;
      if (Number.isFinite(insertRes.insertId)) {
        reservationId = insertRes.insertId;
      } else if (Number.isFinite(insertRes.raw?.insertId)) {
        reservationId = insertRes.raw.insertId;
      }
      if (!Number.isFinite(reservationId)) {
        throw new Error('Nu am putut salva rezervarea.');
      }
      reservationIds.push(Number(reservationId));

      let promoPiece = 0;
      if (priceInfo && promoRemaining > 0) {
        const perSeatPrice = Number(priceInfo.price || 0);
        const potential = Math.max(0, perSeatPrice);
        promoPiece = Math.min(promoRemaining, potential);
        if (promoPiece > 0) {
          await execQuery(
            conn,
            `
            INSERT INTO reservation_discounts
              (reservation_id, discount_type_id, promo_code_id, discount_amount, discount_snapshot)
            VALUES (?, NULL, ?, ?, ?)
            `,
            [reservationId, promoResult.promo_code_id, promoPiece, promoResult.value_off]
          );
          await execQuery(
            conn,
            `
            INSERT INTO promo_code_usages (promo_code_id, reservation_id, phone, discount_amount)
            VALUES (?, ?, ?, ?)
            `,
            [promoResult.promo_code_id, reservationId, cleanPhone || null, promoPiece]
          );
          promoRemaining = +(promoRemaining - promoPiece).toFixed(2);
        }
      }

      if (priceInfo) {
        await execQuery(
          conn,
          `
          INSERT INTO reservation_pricing (reservation_id, price_value, price_list_id, pricing_category_id, booking_channel)
          VALUES (?, ?, ?, ?, 'online')
          `,
          [
            reservationId,
            Math.max(0, Number(priceInfo.price || 0) - Number(promoPiece || 0)),
            priceInfo.price_list_id,
            priceInfo.pricing_category_id,
          ]
        );
      }

      await execQuery(
        conn,
        `
        INSERT INTO reservation_events (reservation_id, action, actor_id, details)
        VALUES (?, 'create', NULL, JSON_OBJECT('channel', 'online'))
        `,
        [reservationId]
      );
    }

    if (seatIds.length) {
      await execQuery(
        conn,
        `DELETE FROM reservation_intents WHERE trip_id = ? AND seat_id IN (${placeholders})`,
        [tripId, ...seatIds],
      );
    }

    await conn.commit();
    conn.release();

    const baseAmount = priceInfo ? Number(priceInfo.price) * seatIds.length : null;
    const discountTotal = promoResult?.discount_amount ? Number(promoResult.discount_amount) : 0;
    const totalAmount = baseAmount !== null ? Math.max(0, Number(baseAmount) - Number(discountTotal)) : null;

    res.status(201).json({
      success: true,
      reservation_ids: reservationIds,
      trip_id: tripId,
      amount_total: totalAmount,
      discount_total: discountTotal,
      currency: priceInfo ? 'RON' : null,
    });
  } catch (err) {
    try {
      await conn.rollback();
    } catch (_) {
      /* ignore */
    }
    conn.release();
    console.error('[public/reservations] error', err);
    res.status(500).json({ error: 'Eroare la salvarea rezervării.' });
  }
});

module.exports = router;
