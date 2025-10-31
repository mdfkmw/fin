import React, { useState, useEffect, useMemo } from 'react';
import axios from 'axios';

export default function DiscountAppliesTab() {
  const [discounts, setDiscounts] = useState([]);
  const [schedules, setSchedules] = useState([]);
  const [selDisc, setSelDisc] = useState('');
  const [checked, setChecked] = useState(new Set());
  const [pricingCategories, setPricingCategories] = useState([]);
  const [selCategory, setSelCategory] = useState('');
  const [catChecked, setCatChecked] = useState(new Set());

  // sorting state
  const [sortConfig, setSortConfig] = useState({ key: 'route_name', direction: 'asc' });

  useEffect(() => {
    axios.get('/api/discount-types').then(r => setDiscounts(r.data));
    axios.get('/api/discount-types/schedules/all').then(r => setSchedules(r.data));
    axios
      .get('/api/pricing-categories')
      .then(r => {
        const data = Array.isArray(r.data) ? r.data : [];
        setPricingCategories(data);
      })
      .catch(() => setPricingCategories([]));
  }, []);

  useEffect(() => {
    if (!selDisc) {
      setChecked(new Set());
      return;
    }
    axios.get(`/api/discount-types/${selDisc}/schedules`).then(r => setChecked(new Set(r.data)));
  }, [selDisc]);

  useEffect(() => {
    if (!selCategory) {
      setCatChecked(new Set());
      return;
    }
    axios
      .get(`/api/pricing-categories/${selCategory}/schedules`)
      .then(r => setCatChecked(new Set(r.data)))
      .catch(() => setCatChecked(new Set()));
  }, [selCategory]);

  function toggle(id) {
    setChecked(prev => {
      const nxt = new Set(prev);
      nxt.has(id) ? nxt.delete(id) : nxt.add(id);
      return nxt;
    });
  }

  function save() {
    axios
      .put(`/api/discount-types/${selDisc}/schedules`, { scheduleIds: Array.from(checked) })
      .then(() => alert('Salvat!'))
      .catch(() => alert('Eroare la salvare'));
  }

  function toggleCategory(id) {
    setCatChecked(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }

  function saveCategories() {
    axios
      .put(`/api/pricing-categories/${selCategory}/schedules`, { scheduleIds: Array.from(catChecked) })
      .then(() => alert('Salvat!'))
      .catch(() => alert('Eroare la salvare'));
  }

  // sort handler
  const requestSort = key => {
    let direction = 'asc';
    if (sortConfig.key === key && sortConfig.direction === 'asc') {
      direction = 'desc';
    }
    setSortConfig({ key, direction });
  };

  const sortedSchedules = useMemo(() => {
    const sortable = [...schedules];
    sortable.sort((a, b) => {
      let aVal = a[sortConfig.key];
      let bVal = b[sortConfig.key];
      if (typeof aVal === 'string') aVal = aVal.toLowerCase();
      if (typeof bVal === 'string') bVal = bVal.toLowerCase();
      if (aVal < bVal) return sortConfig.direction === 'asc' ? -1 : 1;
      if (aVal > bVal) return sortConfig.direction === 'asc' ? 1 : -1;
      return 0;
    });
    return sortable;
  }, [schedules, sortConfig]);

  return (
    <div className="p-6">
      <h2 className="text-lg font-semibold mb-4">Se aplică la</h2>

      <section className="mb-10">
        <h3 className="text-base font-semibold mb-2">Reducerile</h3>
        <div className="mb-4">
          <select
            className="p-2 text-sm border rounded"
            value={selDisc}
            onChange={e => setSelDisc(e.target.value)}
          >
            <option value="">Alege reducere…</option>
            {discounts.map(d => (
              <option key={d.id} value={d.id}>
                {d.label}
              </option>
            ))}
          </select>
        </div>

        <div className="overflow-x-auto">
          <table className="w-auto text-sm table-auto border-collapse">
            <thead>
              <tr>
                <th
                  onClick={() => requestSort('route_name')}
                  className="p-1 border text-left cursor-pointer select-none bg-gray-200"
                >
                  Traseu {sortConfig.key === 'route_name' ? (sortConfig.direction === 'asc' ? '▲' : '▼') : ''}
                </th>
                <th
                  onClick={() => requestSort('departure')}
                  className="p-1 border text-left cursor-pointer select-none bg-gray-200"
                >
                  Ora {sortConfig.key === 'departure' ? (sortConfig.direction === 'asc' ? '▲' : '▼') : ''}
                </th>
                <th
                  onClick={() => requestSort('direction')}
                  className="p-1 border text-left cursor-pointer select-none bg-gray-200"
                >
                  Direcție {sortConfig.key === 'direction' ? (sortConfig.direction === 'asc' ? '▲' : '▼') : ''}
                </th>
                <th className="p-1 border text-left bg-gray-200">Aplică</th>
              </tr>
            </thead>
            <tbody>
              {sortedSchedules.map((s, idx) => (
                <tr
                  key={s.id}
                  className={idx % 2 === 0 ? 'bg-white' : 'bg-gray-50'}
                >
                  <td className="p-1 border">{s.route_name}</td>
                  <td className="p-1 border">{s.departure}</td>
                  <td className="p-1 border">{s.direction}</td>
                  <td className="p-1 border text-center">
                    <input
                      type="checkbox"
                      checked={checked.has(s.id)}
                      onChange={() => toggle(s.id)}
                      disabled={!selDisc}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="text-left mt-4">
          <button
            className="px-3 py-1 text-sm bg-green-600 text-white rounded"
            disabled={!selDisc}
            onClick={save}
          >
            Salvează
          </button>
        </div>
      </section>

      <section>
        <h3 className="text-base font-semibold mb-2">Categorii de preț</h3>
        <div className="mb-4">
          <select
            className="p-2 text-sm border rounded"
            value={selCategory}
            onChange={e => setSelCategory(e.target.value)}
          >
            <option value="">Alege categorie…</option>
            {pricingCategories.map(c => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </div>

        <div className="overflow-x-auto">
          <table className="w-auto text-sm table-auto border-collapse">
            <thead>
              <tr>
                <th
                  onClick={() => requestSort('route_name')}
                  className="p-1 border text-left cursor-pointer select-none bg-gray-200"
                >
                  Traseu {sortConfig.key === 'route_name' ? (sortConfig.direction === 'asc' ? '▲' : '▼') : ''}
                </th>
                <th
                  onClick={() => requestSort('departure')}
                  className="p-1 border text-left cursor-pointer select-none bg-gray-200"
                >
                  Ora {sortConfig.key === 'departure' ? (sortConfig.direction === 'asc' ? '▲' : '▼') : ''}
                </th>
                <th
                  onClick={() => requestSort('direction')}
                  className="p-1 border text-left cursor-pointer select-none bg-gray-200"
                >
                  Direcție {sortConfig.key === 'direction' ? (sortConfig.direction === 'asc' ? '▲' : '▼') : ''}
                </th>
                <th className="p-1 border text-left bg-gray-200">Disponibil</th>
              </tr>
            </thead>
            <tbody>
              {sortedSchedules.map((s, idx) => (
                <tr
                  key={s.id}
                  className={idx % 2 === 0 ? 'bg-white' : 'bg-gray-50'}
                >
                  <td className="p-1 border">{s.route_name}</td>
                  <td className="p-1 border">{s.departure}</td>
                  <td className="p-1 border">{s.direction}</td>
                  <td className="p-1 border text-center">
                    <input
                      type="checkbox"
                      checked={catChecked.has(s.id)}
                      onChange={() => toggleCategory(s.id)}
                      disabled={!selCategory}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="text-left mt-4">
          <button
            className="px-3 py-1 text-sm bg-green-600 text-white rounded"
            disabled={!selCategory}
            onClick={saveCategories}
          >
            Salvează
          </button>
        </div>
      </section>
    </div>
  );
}
