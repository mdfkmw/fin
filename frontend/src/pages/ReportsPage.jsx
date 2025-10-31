import { useEffect, useState } from 'react';
import OperatorSelect from '../components/OperatorSelect';
import DateRangePicker from '../components/DateRangePicker';
import AgencySelect from '../components/Reports/AgencySelect';
import AgentSelect from '../components/Reports/AgentSelect';
import TripsTable from '../components/Reports/TripsTable';

export default function ReportsPage() {
  const today = new Date().toISOString().slice(0, 10);

  const [operatorId, setOperatorId] = useState(null);
  const [routeOptions, setRouteOptions] = useState([]);
  const [selectedRoute, setSelectedRoute] = useState(null);
  const [agencyId, setAgencyId] = useState(null);
  const [agentId, setAgentId] = useState(null);
  const [range, setRange] = useState({ start: today, end: today });
  const [hourOptions, setHourOptions] = useState([]);   // orele rutei selectate
  const [selectedHour, setSelectedHour] = useState(null); // "HH:MM" sau null


  const [data, setData] = useState({ trips: [], summary: {}, toHandOver: 0 });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  



  // 👇 hardcode pentru test
  const HARDCODED_EMPLOYEE_ID = 12;

  // State pentru „predă banii”
  const [unsettled, setUnsettled] = useState([]);       // grupuri pe operator
  const [handoverHistory, setHandoverHistory] = useState([]);
  const [handoverBusy, setHandoverBusy] = useState(false);

  const fetchUnsettled = async () => {
    const res = await fetch(`/api/cash/unsettled?employeeId=${HARDCODED_EMPLOYEE_ID}`);
    const data = await res.json();
    setUnsettled(Array.isArray(data) ? data : []);
  };

  const fetchHandoverHistory = async () => {
    const res = await fetch(`/api/cash/handovers/history?employeeId=${HARDCODED_EMPLOYEE_ID}`);
    const data = await res.json();
    setHandoverHistory(Array.isArray(data) ? data : []);
  };

  useEffect(() => {
    fetchUnsettled();
    fetchHandoverHistory();
  }, []);

const unsettledTotal = unsettled.reduce((s, r) => s + Number(r.total_amount || 0), 0);


  const handlePredaBanii = async () => {
    if (!unsettled.length) {
      alert('Nu ai nimic de predat.');
      return;
    }
    if (!window.confirm('Predai toate încasările CASH nepredate (grupate pe operator)?')) return;

    setHandoverBusy(true);
    try {
      const res = await fetch('/api/cash/handovers/preda', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ employeeId: HARDCODED_EMPLOYEE_ID }),
      });
      const data = await res.json();
      if (data?.ok) {
        // reîncarcă listele
        await fetchUnsettled();
        await fetchHandoverHistory();
        const total = (data.handovers || []).reduce((s, h) => s + Number(h.amount || 0), 0);
        alert(`Predare reușită: ${data.handovers?.length || 0} lot(uri), total ${total} lei.`);
      } else {
        alert('A apărut o eroare la predare.');
      }
    } catch (e) {
      console.error(e);
      alert('Eroare la predare.');
    } finally {
      setHandoverBusy(false);
    }
  };


  // Populează dropdown-ul de rute apelând endpoint-ul dedicat
useEffect(() => {
  if (!operatorId || isNaN(Number(operatorId))) {
    setRouteOptions([]);
    return;
  }

  fetch(`/api/routes?operator_id=${Number(operatorId)}&date=${range.start}`)
    .then(r => r.json())
    .then(json => {
      // endpointul poate întoarce fie {routes:[...]} fie direct [...]
      const arr = Array.isArray(json?.routes) ? json.routes
                : Array.isArray(json)         ? json
                : [];
      const mapped = arr.map(rt => {
        const hours = Array.isArray(rt.schedules)
          ? rt.schedules
              .map(s => ({
                departure: s?.departure,
                direction: s?.direction || '',
              }))
              .filter(s => s.departure)
          : [];
        return { id: rt.id, name: rt.name, hours };
      });
      setRouteOptions(mapped);
    })
   .catch(console.error);
}, [operatorId, range.start]);


  // Când se schimbă ruta sau lista de rute, calculează orele disponibile.
  // Dacă nu e selectată o rută => folosim uniunea tuturor orelor.
  useEffect(() => {
    let hours = [];
    if (selectedRoute) {
      const route = routeOptions.find(r => String(r.id) === String(selectedRoute));
      hours = Array.isArray(route?.hours) ? route.hours : [];
    } else {
      const all = [];
      for (const r of routeOptions) {
        (r.hours || []).forEach(h => all.push(h));
      }
      hours = all;
    }
    // ordonăm după direcție și oră
    const sorted = hours
      .sort((a, b) => {
        if (a.direction === b.direction) return a.departure.localeCompare(b.departure);
        return a.direction.localeCompare(b.direction);
      });
    setHourOptions(sorted);
    if (selectedHour && !sorted.some(h => h.departure === selectedHour)) {
      setSelectedHour(null);
    }
  }, [selectedRoute, routeOptions]);


  // Apoi fetch-ul principal pentru tabel rămâne separat:
  useEffect(() => {
    if (!operatorId) return;
    setLoading(true);

    const params = {
      operator_id: operatorId,
      start: range.start,
      end: range.end,
    };
    if (selectedRoute) params.route_id = selectedRoute;
    if (agencyId) params.agency_id = agencyId;
    if (agentId) params.agent_id = agentId;
    if (selectedHour) params.hour = selectedHour;
    fetch(`/api/reports/trips?${new URLSearchParams(params)}`)
      .then(r => r.json())
      .then(json => {
        if (json.error) throw new Error(json.error);
        setData(json);
        setError(null);
      })
      .catch(err => setError(err.message))
      .finally(() => setLoading(false));
  }, [operatorId, range, selectedRoute, agencyId, agentId, selectedHour]);

  return (
    <div className="p-4 flex flex-col gap-4">
      <div className="flex flex-wrap gap-4 items-end">
        <OperatorSelect value={operatorId} onChange={setOperatorId} />
        <select
          value={selectedRoute ?? ''}
          onChange={e => setSelectedRoute(e.target.value || null)}
          className="border rounded px-2 py-1"
        >
          <option value="">Toate rutele</option>
          {routeOptions.map(r => (
            <option key={r.id} value={r.id}>{r.name}</option>
          ))}
        </select>
        <select
          value={selectedHour ?? ''}
          onChange={e => setSelectedHour(e.target.value || null)}
          className="border rounded px-2 py-1"
          disabled={!hourOptions.length}
        >
          <option value="">{hourOptions.length ? 'Toate orele' : 'Fără ore'}</option>
{hourOptions.map((h, idx) => (
  <option
    key={`${h.direction || 'tur'}-${h.departure}-${h.route_name || ''}-${idx}`}
    value={h.departure}
  >
    {`${h.direction?.toUpperCase() || 'TUR'} ${h.departure}${
      h.route_name ? ' – ' + h.route_name : ''
    }`}
  </option>
))}

        </select>
        <AgencySelect value={agencyId} onChange={id => { setAgencyId(id); setAgentId(null); }} />
        <AgentSelect value={agentId} onChange={setAgentId} agencyId={agencyId} />
        <DateRangePicker value={range} onChange={setRange} />
      </div>

      {error && <div className="text-red-600">{error}</div>}
      {loading && <div className="animate-pulse text-gray-400">Se încarcă…</div>}

      {!loading && !error && (
        <>
          <TripsTable rows={data.trips} />

          {/* ====== CASH: Bani de predat & Istoric predări ====== */}
          <div className="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-4">
            {/* Bani de predat */}
            <div className="border rounded-xl p-4 shadow-sm">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-lg font-semibold">Bani de predat (agent #{HARDCODED_EMPLOYEE_ID})</h3>
                <button
                  onClick={handlePredaBanii}
                  disabled={!unsettled.length || handoverBusy}
                  className={`px-3 py-2 rounded-lg text-white ${(!unsettled.length || handoverBusy) ? 'bg-gray-400' : 'bg-blue-600 hover:bg-blue-700'}`}
                >
                  {handoverBusy ? 'Se predă…' : 'Predă banii'}
                </button>
              </div>

              {unsettled.length === 0 ? (
                <div className="text-sm text-gray-500">Nu există plăți CASH nepredate.</div>
              ) : (
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left border-b">
                      <th className="py-2">Operator</th>
                      <th className="py-2"># Plăți</th>
                      <th className="py-2">Sumă</th>
                    </tr>
                  </thead>
                  <tbody>
                    {unsettled.map((row) => (
                      <tr key={row.operator_id} className="border-b last:border-0">
                        <td className="py-2">{row.operator_name}</td>
                        <td className="py-2">{row.payments_count}</td>
                        <td className="py-2">{Number(row.total_amount || 0).toFixed(2)} lei</td>
                      </tr>
                    ))}
                    <tr className="font-semibold">
                      <td className="py-2">TOTAL</td>
                      <td className="py-2">
                        {unsettled.reduce((s, r) => s + Number(r.payments_count || 0), 0)}
                      </td>
                      <td className="py-2">{unsettledTotal.toFixed(2)} lei</td>
                    </tr>
                  </tbody>
                </table>
              )}
            </div>

            {/* Istoric predări */}
            <div className="border rounded-xl p-4 shadow-sm">
              <h3 className="text-lg font-semibold mb-3">Istoric predări</h3>
              {handoverHistory.length === 0 ? (
                <div className="text-sm text-gray-500">Încă nu există predări.</div>
              ) : (
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left border-b">
                      <th className="py-2">Data</th>
                      <th className="py-2">Operator</th>
                      <th className="py-2"># Plăți</th>
                      <th className="py-2">Sumă</th>
                    </tr>
                  </thead>
                  <tbody>
                    {handoverHistory.map((h) => (
                      <tr key={h.id} className="border-b last:border-0">
                        <td className="py-2">{new Date(h.created_at).toLocaleString()}</td>
                        <td className="py-2">{h.operator_name}</td>
                        <td className="py-2">{h.payments_count}</td>
                        <td className="py-2">{Number(h.amount || 0).toFixed(2)} lei</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </div>


          <div className="mt-4 flex items-center justify-between">
            <div className="font-semibold">Achitate</div>
          </div>


          {/* SUMAR – ACHITATE (zebra) */}
          <table className="w-full mt-4 text-sm border">
            <tbody className="[&>tr:nth-child(odd)]:bg-gray-50">
              <tr>
                <td className="px-2 py-1 whitespace-nowrap">Bilete achitate (nr.)</td>
                <td className="px-2 py-1 text-right">{data.summary?.paid_seats ?? 0}</td>
              </tr>
              <tr>
                <td className="px-2 py-1 whitespace-nowrap">Încasări nete (lei)</td>
                <td className="px-2 py-1 text-right">{Number(data.summary?.paid_total ?? 0).toFixed(2)}</td>
              </tr>
              <tr>
                <td className="px-2 py-1 whitespace-nowrap">Reduceri aplicate (lei)</td>
                <td className="px-2 py-1 text-right">{Number(data.summary?.paid_discounts ?? 0).toFixed(2)}</td>
              </tr>
              <tr>
                <td className="px-2 py-1 whitespace-nowrap font-semibold">Bani de predat (cash)</td>
                <td className="px-2 py-1 text-right font-semibold">{unsettledTotal.toFixed(2)}</td>
              </tr>
            </tbody>
          </table>

          {/* SUMAR – DOAR REZERVĂRI (zebra) */}
          <table className="w-full mt-4 text-sm border">
            <tbody className="[&>tr:nth-child(odd)]:bg-gray-50">
              <tr>
                <td className="px-2 py-1 whitespace-nowrap">Rezervări neplătite (nr.)</td>
                <td className="px-2 py-1 text-right">{data.summary?.reserved_seats ?? 0}</td>
              </tr>
              <tr>
                <td className="px-2 py-1 whitespace-nowrap">Valoare rezervări (lei)</td>
                <td className="px-2 py-1 text-right">{Number(data.summary?.reserved_total ?? 0).toFixed(2)}</td>
              </tr>
              <tr>
                <td className="px-2 py-1 whitespace-nowrap">Reduceri rezervări (lei)</td>
                <td className="px-2 py-1 text-right">{Number(data.summary?.reserved_discounts ?? 0).toFixed(2)}</td>
              </tr>
            </tbody>
          </table>

          {/* (Opțional) Reduceri pe tip – apare doar dacă backend a trimis discountsByType */}
          {Array.isArray(data.discountsByType) && data.discountsByType.length > 0 && (
            <div className="mt-4">
              <div className="font-semibold mb-1">Reducerile pe tip</div>
              <table className="w-full text-sm border">
                <thead className="bg-gray-100">
                  <tr>
                    <th className="border px-2 py-1 text-left">Tip reducere</th>
                    <th className="border px-2 py-1 text-right">Nr. achitate</th>
                    <th className="border px-2 py-1 text-right">Lei achitate</th>
                    <th className="border px-2 py-1 text-right">Nr. rezervări</th>
                    <th className="border px-2 py-1 text-right">Lei rezervări</th>
                  </tr>
                </thead>
                <tbody className="[&>tr:nth-child(odd)]:bg-gray-50">
                  {data.discountsByType.map(d => (
                    <tr key={d.discount_type_id}>
                      <td className="border px-2 py-1">{d.discount_label}</td>
                      <td className="border px-2 py-1 text-right">{d.paid_count}</td>
                      <td className="border px-2 py-1 text-right">{Number(d.paid_total).toFixed(2)}</td>
                      <td className="border px-2 py-1 text-right">{d.reserved_count}</td>
                      <td className="border px-2 py-1 text-right">{Number(d.reserved_total).toFixed(2)}</td>
                    </tr>
                  ))}
                  <tr className="font-semibold">
                    <td className="border px-2 py-1">TOTAL</td>
                    <td className="border px-2 py-1 text-right">
                      {data.discountsByType.reduce((s, d) => s + Number(d.paid_count || 0), 0)}
                    </td>
                    <td className="border px-2 py-1 text-right">
                      {data.discountsByType.reduce((s, d) => s + Number(d.paid_total || 0), 0).toFixed(2)}
                    </td>
                    <td className="border px-2 py-1 text-right">
                      {data.discountsByType.reduce((s, d) => s + Number(d.reserved_count || 0), 0)}
                    </td>
                    <td className="border px-2 py-1 text-right">
                      {data.discountsByType.reduce((s, d) => s + Number(d.reserved_total || 0), 0).toFixed(2)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          )}


        </>
      )}







    </div>
  );
}
