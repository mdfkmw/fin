import React, { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';


function AuditMini({ reservationId }) {
  const [rows, setRows] = useState([]);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');

  const toggle = () => {
    if (!open) {
      setLoading(true);
      fetch(`/api/audit-logs?reservation_id=${reservationId}`)
        .then(r => r.ok ? r.json() : r.json().then(j => Promise.reject(j?.error || 'Eroare')))
        .then(j => { setRows(Array.isArray(j) ? j : []); setErr(''); })
        .catch(e => setErr(String(e)))
        .finally(() => setLoading(false));
    }
    setOpen(!open);
  };

  return (
    <div>
      <button className="text-blue-600 underline" onClick={toggle}>
        {open ? 'Ascunde' : 'Vezi'}
      </button>
      {open && (
        <div className="mt-2 border rounded p-2 bg-gray-50">
          {loading ? 'Se încarcă…' : err ? <span className="text-red-600">{err}</span> : (
            rows.length === 0 ? '—' : (
              <>
                {/* ⬇️ rezumat ușor de citit */}
                <div className="text-xs mb-2">
                  {(() => {
                    const move = rows.find(r => (r.action_label || r.action) === 'reservation.moveToOtherTrip' || (r.action || '').startsWith('reservation.move'));
                    const pay = rows.filter(r => (r.action || '') === 'payment.capture').sort((a, b) => (a.at > b.at ? -1 : 1))[0];
                    const who = (move && (move.actor_name || move.actor_id)) || (pay && (pay.actor_name || pay.actor_id)) || '';
                    const moveText = move ? (
                      <span>
                        <b>Mutată</b> pe {move.at} de <b>{who}</b>
                        {move.from_trip_date ? <> — de la <b>{move.from_trip_date} {move.from_hour || ''}</b> ({move.from_route_name || ''} · {move.from_segment || ''} · loc {move.from_seat || '—'})</> : null}
                        {move.trip_date ? <> → la <b>{move.trip_date} {move.hour || ''}</b> ({move.route_name || ''} · {move.segment || ''} · loc {move.seat || '—'})</> : null}
                      </span>
                    ) : null;
                    const payText = pay ? (
                      <span>
                        {move ? ' · ' : ''}<b>Plată</b>: {pay.amount ?? '—'} {pay.payment_method ? `(${pay.payment_method})` : ''}{pay.transaction_id ? `, txn ${pay.transaction_id}` : ''}{pay.at ? `, la ${pay.at}` : ''}
                      </span>
                    ) : null;
                    return (moveText || payText) ? <div>{moveText}{payText}</div> : null;
                  })()}
                </div>

                {/* timeline detaliat (opțional) */}
                <table className="w-full text-xs">
                  <thead>
                    <tr>
                      <th className="border p-1">Dată</th>
                      <th className="border p-1">Acțiune</th>
                      <th className="border p-1">Actor</th>
                      <th className="border p-1">Sumă</th>
                      <th className="border p-1">Metodă</th>
                      <th className="border p-1">Channel</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map(ev => (
                      <tr key={ev.event_id}>
                        <td className="border p-1">{ev.at}</td>
                        <td className="border p-1">{ev.action_label || ev.action}</td>
                        <td className="border p-1">{ev.actor_name || ev.actor_id}</td>
                        <td className="border p-1">{ev.amount ?? ''}</td>
                        <td className="border p-1">{ev.payment_method ?? ''}</td>
                        <td className="border p-1">{ev.channel ?? ''}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </>
            )
          )}
        </div>
      )}
    </div>
  );
}


export default function PassengerReport() {
  const { personId } = useParams();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [editName, setEditName] = useState('');
  const [editPhone, setEditPhone] = useState('');
  const [editNotes, setEditNotes] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetch(`/api/people/${personId}/report`)
      .then(res => res.json())
      .then(json => {
        setData(json);
        setLoading(false);
        setEditName(json.personName || '');
        setEditPhone(json.personPhone || '');
        setEditNotes(json.personNotes || '');
      })
      .catch(err => {
        console.error('Eroare la fetch raport:', err);
        setLoading(false);
      });
  }, [personId]);

  if (loading) return <div className="p-4">Se încarcă...</div>;
  if (!data) return <div className="p-4 text-red-500">Eroare la încărcare</div>;

  const {
    personName = '',
    personPhone = '',
    reservations = [],
    noShows = [],
    blacklist
  } = data;

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <h1 className="text-xl font-bold mb-4">
        Raport pasager ID #{personId}
        {personName && ` - ${personName}`}
      </h1>


      {data.blacklist && (
        <div className="bg-red-100 border border-red-400 text-red-700 p-4 rounded mb-6">
          🚫 În blacklist: {data.blacklist.reason} <br />
          <span className="text-sm italic">
            Adăugat de: {data.blacklist.added_by_name || '—'}
            &nbsp;•&nbsp; la: {new Date(data.blacklist.created_at).toLocaleString()}
          </span>
        </div>
      )}

      {/* Editare rapidă: nume / telefon / note */}
      <section className="mb-6 bg-white border rounded p-4">
        <div className="grid md:grid-cols-3 gap-4">
          <div>
            <label className="block text-sm text-gray-600 mb-1">Nume</label>
            <input value={editName} onChange={e => setEditName(e.target.value)}
              className="w-full border rounded px-3 py-2" />
          </div>
          <div>
            <label className="block text-sm text-gray-600 mb-1">Telefon</label>
            <input value={editPhone} onChange={e => setEditPhone(e.target.value)}
              className="w-full border rounded px-3 py-2" />
          </div>
          <div className="md:col-span-3">
            <label className="block text-sm text-gray-600 mb-1">Observații / note</label>
            <textarea value={editNotes} onChange={e => setEditNotes(e.target.value)}
              rows={3} className="w-full border rounded px-3 py-2" />
          </div>
        </div>
        <div className="mt-3">
          <button
            disabled={saving}
            onClick={async () => {
              try {
                setSaving(true);
                const r = await fetch(`/api/people/${personId}`, {
                  method: 'PUT',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ name: editName, phone: editPhone, notes: editNotes })
                });
                const js = await r.json();
      if (!r.ok || !js?.success) throw new Error(js?.error || 'Eroare la salvare');
      // reîncarcă raportul ca să vezi valorile (și în DB, și în UI)
      const rep = await fetch(`/api/people/${personId}/report`).then(x => x.json());
      setData(rep);
      setEditName(rep.personName || '');
      setEditPhone(rep.personPhone || '');
      setEditNotes(rep.personNotes || '');
      alert('Salvat.');
              } catch (e) {
                alert(e.message || 'Eroare la salvare');
              } finally {
                setSaving(false);
              }
            }}
            className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
          >
            {saving ? 'Se salvează…' : 'Salvează'}
          </button>
        </div>
      </section>

      <section className="mb-6">
        <h2 className="text-lg font-semibold mb-2">📅 Rezervări</h2>
        {reservations.length === 0 ? (
          <div className="text-gray-500">Nicio rezervare găsită.</div>
        ) : (
          <table className="w-full text-sm border-collapse border">
            <thead>
              <tr className="bg-gray-100">
                <th className="p-2 border">Data călătoriei<br />(Rezervare la)</th>
                <th className="p-2 border">Traseu</th>
                <th className="p-2 border">Ora cursă</th>
                <th className="p-2 border">Segment</th>
                <th className="p-2 border">Loc</th>
                <th className="p-2 border">Status</th>
                <th className="p-2 border">Creată de</th>
                <th className="p-2 border">Preț</th>
                <th className="p-2 border">Reduceri</th>
                <th className="p-2 border">Preț final</th>
                <th className="p-2 border">Canal</th>
                <th className="p-2 border">Istoric</th>
              </tr>
            </thead>
            <tbody>
              {reservations.map((r, index) => {
                const isNoShow = noShows.some(n =>
                  n.date === r.date &&
                  n.time === r.time &&
                  // comparațiile vechi pe text nu mai sunt relevante,
                  // am trecut la ID-uri; lăsăm doar highlight pe data/ora
                  true
                );
                return (
                  <tr
                    key={r.id || index}
                    style={{ backgroundColor: isNoShow ? '#ffe6e6' : 'white' }}
                  >
                    <td className="p-2 border">
                      {new Date(r.date).toLocaleDateString('ro-RO')}
                      <br />
                      <span className="text-xs text-gray-500">
                        {r.reservation_time
                          ? new Date(r.reservation_time).toLocaleTimeString('ro-RO', {
                            hour: '2-digit',
                            minute: '2-digit',
                            timeZone: 'Europe/Bucharest'
                          })
                          : ''
                        }
                      </span>
                    </td>
                    <td className="p-2 border">{r.route_name}</td>
                    <td className="p-2 border">{r.time.substring(0, 5)}</td>
                    <td className="p-2 border">{(r.board_name || '')} &rarr; {(r.exit_name || '')}</td>
                    <td className="p-2 border">{r.seat_label}</td>
                    <td className="p-2 border">
                      {typeof r.status === 'string' ? (
                        <span
                          className={
                            `px-2 py-0.5 rounded text-xs ${r.status.toLowerCase() === 'cancelled'
                              ? 'bg-red-100 text-red-700'
                              : 'bg-green-100 text-green-700'
                            }`
                          }
                        >
                          {r.status.toLowerCase() === 'cancelled' ? 'Anulată' : 'Activă'}
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 rounded text-xs bg-gray-100 text-gray-600">—</span>
                      )}
                    </td>
                    <td className="p-2 border">{r.reserved_by || '—'}</td>
                    <td className="p-2 border">{r.price_base ?? '—'}</td>
                    <td className="p-2 border">{r.discount_summary || '—'}</td>
                    <td className="p-2 border">{r.price_final ?? '—'}</td>
                    <td className="p-2 border">{r.booking_channel === 'online' ? 'online' : '—'}</td>
                    <td className="p-2 border">
                      {r.id ? <AuditMini reservationId={r.id} /> : '—'}
                    </td>

                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </section>

      <section className="mb-6">
        <h2 className="text-lg font-semibold mb-2">⛔ Neprezentări</h2>
        {noShows.length === 0 ? (
          <div className="text-gray-500">Nu există neprezentări.</div>
        ) : (
          <table className="w-full text-sm border-collapse border">
            <thead>
              <tr className="bg-gray-100">
                <th className="p-2 border">Data</th>
                <th className="p-2 border">Traseu</th>
                <th className="p-2 border">Ora</th>
                <th className="p-2 border">Segment</th>
                <th className="p-2 border">Loc</th>
                <th className="p-2 border">Marcat de</th>
                <th className="p-2 border">La</th>
              </tr>
            </thead>
            <tbody>
              {noShows.map((n) => (
                <tr key={n.id}>
                  <td className="p-2 border">{n.date}</td>
                  <td className="p-2 border">{n.route_name}</td>
                  <td className="p-2 border">{n.time}</td>
                  <td className="p-2 border">{(n.board_name || '')} &rarr; {(n.exit_name || '')}</td>
                  <td className="p-2 border">{n.seat_label}</td>
                  <td className="p-2 border">{n.marked_by || '—'}</td>
                  <td className="p-2 border">{n.marked_at || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>





      <div className="mt-6">
        <Link to="/" className="text-blue-600 hover:underline">← Înapoi la rezervări</Link>
      </div>
    </div>
  );
}
