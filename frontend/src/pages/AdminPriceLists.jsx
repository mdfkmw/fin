import React, { useEffect, useMemo, useState } from 'react';

const formatValue = (value) => {
  if (value == null || value === '') return '';
  const num = Number(value);
  if (Number.isNaN(num)) return '';
  return Number.isInteger(num) ? String(num) : num.toFixed(2).replace(/\.00$/, '').replace(/(\.\d*?[1-9])0+$/, '$1');
};

const createEmptyGrid = (stationNames) => {
  const base = {};
  stationNames.forEach((from) => {
    base[from] = {};
    stationNames.forEach((to) => {
      base[from][to] = { price: '', price_return: '', r_price: '', r_price_return: '' };
    });
  });
  return base;
};

export default function AdminPriceLists() {
  const [routes, setRoutes] = useState([]);
  const [categories, setCategories] = useState([]);
  const [stationsRaw, setStationsRaw] = useState([]);
  const [stations, setStations] = useState([]);
  const [grid, setGrid] = useState({});
  const [versions, setVersions] = useState([]);
  const [loadingItems, setLoadingItems] = useState(false);

  const [selectedRoute, setSelectedRoute] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('');
  const [effectiveDate, setEffectiveDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [selectedVersion, setSelectedVersion] = useState('');

  const nameToId = useMemo(() => {
    const map = new Map();
    stationsRaw.forEach((station) => {
      map.set(station.name, station.station_id);
    });
    return map;
  }, [stationsRaw]);

  useEffect(() => {
    const bootstrap = async () => {
      try {
        const [routesRes, categoriesRes] = await Promise.all([
          fetch('/api/routes'),
          fetch('/api/pricing-categories'),
        ]);
        const [routesJson, categoriesJson] = await Promise.all([
          routesRes.ok ? routesRes.json() : Promise.resolve([]),
          categoriesRes.ok ? categoriesRes.json() : Promise.resolve([]),
        ]);
        setRoutes(Array.isArray(routesJson) ? routesJson : []);
        setCategories(Array.isArray(categoriesJson) ? categoriesJson : []);
      } catch (err) {
        console.error('AdminPriceLists: nu pot încărca rutele sau categoriile', err);
        setRoutes([]);
        setCategories([]);
      }
    };

    bootstrap();
  }, []);

  useEffect(() => {
    if (categories.length === 0 || selectedCategory) return;
    const firstActive = categories[0]?.id;
    if (firstActive) {
      setSelectedCategory(String(firstActive));
    }
  }, [categories, selectedCategory]);

  useEffect(() => {
    // reset sincron (prevenim wipe-ul ulterior al versiunilor)
    setStationsRaw([]);
    setStations([]);
    setGrid({});
    setVersions([]);
    setSelectedVersion('');

    if (!selectedRoute) return;

    const ac = new AbortController();
    const loadStations = async () => {
      try {
        const res = await fetch(`/api/routes/${selectedRoute}/stations`, { signal: ac.signal });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        if (ac.signal.aborted) return;
        const sorted = Array.isArray(data)
          ? [...data].sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0))
          : [];
        const names = sorted.map((s) => s.name);
        setStationsRaw(sorted);
        setStations(names);

      } catch (err) {
        if (err.name !== 'AbortError') {
          console.error('AdminPriceLists: nu pot încărca stațiile rutei', err);
        }
        // deja am resetat sincron mai sus
      }
    };
    loadStations();

    return () => ac.abort();
  }, [selectedRoute]);

  useEffect(() => {
    if (!selectedRoute || !selectedCategory || !effectiveDate) {
      setVersions([]);
      setSelectedVersion('');
      return;
    }


    const ac = new AbortController();
    const loadVersions = async () => {
      try {
        const res = await fetch(
          `/api/price-lists?route=${selectedRoute}&category=${selectedCategory}&date=${effectiveDate}`,
          { signal: ac.signal }
        );
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        if (ac.signal.aborted) return;
        const list = Array.isArray(data) ? data : [];
        setVersions(list);
        setSelectedVersion(list[0] ? String(list[0].id) : '');
      } catch (err) {
        if (err.name !== 'AbortError') {
          console.error('AdminPriceLists: nu pot încărca versiunile', err);
        }
        setVersions([]);
        setSelectedVersion('');
      }
    };

    loadVersions();
    return () => ac.abort();
  }, [selectedRoute, selectedCategory, effectiveDate]);

  useEffect(() => {
    if (!selectedVersion) {
      if (stations.length) {
        setGrid(createEmptyGrid(stations));
      }
      return;
    }


    const ac = new AbortController();
    const loadItems = async () => {
      setLoadingItems(true);
      try {
        const res = await fetch(`/api/price-lists/${selectedVersion}/items`, { signal: ac.signal });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        if (ac.signal.aborted) return;
        const items = Array.isArray(data) ? data : [];
        setGrid(() => {
          const next = createEmptyGrid(stations);
          // indexare rapidă a stațiilor pentru a ști care e sus (i<j) și care e jos (i>j)
          const idx = new Map(stations.map((name, i) => [name, i]));
          items.forEach((item) => {
            const fromName = item.from_stop || stationsRaw.find((s) => s.station_id === item.from_station_id)?.name;
            const toName = item.to_stop || stationsRaw.find((s) => s.station_id === item.to_station_id)?.name;
            if (!fromName || !toName) return;
            const i = idx.get(fromName), j = idx.get(toName);
            if (i == null || j == null) return;
            if (!next[fromName]?.[toName]) return;
            if (i < j) {
              // A→B (triunghiul de sus)
              next[fromName][toName].price = formatValue(item.price);
              next[fromName][toName].price_return = formatValue(item.price_return ?? '');
            } else if (i > j) {
              // B→A (triunghiul de jos) — se stochează în câmpurile r_* ale aceleiași celule [fromName][toName]
              next[fromName][toName].r_price = formatValue(item.price);
              next[fromName][toName].r_price_return = formatValue(item.price_return ?? '');
            }
            // i === j (diagonala) ignorăm
          });
          return next;
        });

      } catch (err) {
        if (err.name !== 'AbortError') {
          console.error('AdminPriceLists: nu pot încărca prețurile', err);
        }
        setGrid(createEmptyGrid(stations));
      } finally {
        setLoadingItems(false);
      }
    };

    loadItems();
    return () => ac.abort();
  }, [selectedVersion, stations, stationsRaw]);

  const handleCellChange = (from, to, field, value) => {
    if (value !== '' && !/^\d+(\.\d{0,2})?$/.test(value)) {
      return;
    }
    setGrid((prev) => ({
      ...prev,
      [from]: {
        ...prev[from],
        [to]: {
          ...prev[from][to],
          [field]: value,
        },
      },
    }));
  };

  const handleSave = async () => {
    if (!selectedRoute || !selectedCategory) {
      alert('Selectează traseul și categoria.');
      return;
    }

    const payloadItems = [];
    let validationError = null;
    stations.forEach((from, i) => {
      if (validationError) return;
      stations.forEach((to, j) => {
        if (validationError) return;
        if (j <= i) return; // procesăm o singură dată perechea (i<j)

        // ↑↑ Triunghiul de sus: A→B (T și T/R)
        const cell = grid[from]?.[to];
        if (cell) {
          const hasT = (cell.price ?? '') !== '';
          const hasTR = (cell.price_return ?? '') !== '';
          if (hasT && !/^\d+(\.\d{0,2})?$/.test(cell.price)) {
            validationError = `Preț invalid (T) între ${from} și ${to}`;
            return;
          }
          if (hasTR && !/^\d+(\.\d{0,2})?$/.test(cell.price_return)) {
            validationError = `Preț invalid (T/R) între ${from} și ${to}`;
            return;
          }
          if (hasT || hasTR) {
            payloadItems.push({
              from_station_id: nameToId.get(from),
              to_station_id: nameToId.get(to),
              from_stop: from,
              to_stop: to,
              price: hasT ? Number(cell.price) : 0, // NOT NULL în DB
              price_return: hasTR ? Number(cell.price_return) : null,
              currency: 'RON',
            });
          }
        }
        // ↓↓ Triunghiul de jos: B→A (R și R/T) — se editează în celula inversă [to][from]
        const inv = grid[to]?.[from];
        if (inv) {
          const hasR  = (inv.r_price ?? '') !== '';
          const hasRT = (inv.r_price_return ?? '') !== '';
          if (hasR && !/^\d+(\.\d{0,2})?$/.test(inv.r_price)) {
            validationError = `Preț invalid (R) între ${to} și ${from}`;
            return;
          }
          if (hasRT && !/^\d+(\.\d{0,2})?$/.test(inv.r_price_return)) {
            validationError = `Preț invalid (R/T) între ${to} și ${from}`;
            return;
          }
          if (hasR || hasRT) {
            payloadItems.push({
              from_station_id: nameToId.get(to),   // B
              to_station_id: nameToId.get(from),   // A
              from_stop: to,
              to_stop: from,
              price: hasR ? Number(inv.r_price) : 0, // NOT NULL în DB
              price_return: hasRT ? Number(inv.r_price_return) : null,
              currency: 'RON',
            });
          }
        }
     });
    });
    if (validationError) {
      alert(validationError);
      return;
    }

    if (!payloadItems.length) {
      alert('Completează cel puțin un preț.');
      return;
    }

    try {
      const res = await fetch('/api/price-lists', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          route: Number(selectedRoute),
          category: Number(selectedCategory),
          effective_from: effectiveDate,
          name: `${selectedRoute}-${selectedCategory}-${effectiveDate}`,
          version: 1,
          created_by: 1,
          items: payloadItems,
        }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: 'Eroare la salvare' }));
        throw new Error(err.error || 'Eroare la salvare');
      }
      const data = await res.json();
      alert(`Salvat cu succes! ID: ${data.id}`);

      const refresh = await fetch(
        `/api/price-lists?route=${selectedRoute}&category=${selectedCategory}&date=${effectiveDate}`
      );
      const versionsJson = refresh.ok ? await refresh.json() : [];
      const list = Array.isArray(versionsJson) ? versionsJson : [];
      setVersions(list);
      setSelectedVersion(list[0] ? String(list[0].id) : '');
    } catch (err) {
      console.error('AdminPriceLists: nu pot salva lista de prețuri', err);
      alert(err.message || 'Eroare la salvare');
    }
  };

  const cloneGrid = (source) => {
    const result = {};
    stations.forEach((from) => {
      result[from] = {};
      stations.forEach((to) => {
        const cell = source[from]?.[to] ?? { price: '', price_return: '', r_price: '', r_price_return: '' };
        result[from][to] = {
          price: cell.price ?? '',
          price_return: cell.price_return ?? '',
          r_price: cell.r_price ?? '',
          r_price_return: cell.r_price_return ?? '',
        };
      });
    });
    return result;
  };

// Copiază toate valorile din triunghiul de sus (A→B) în triunghiul de jos (B→A)
const handleCopyOutboundToReturn = () => {
  if (!stations.length) return;
  setGrid((prev) => {
    const next = cloneGrid(prev);
    stations.forEach((from, i) => {
      stations.forEach((to, j) => {
        if (j <= i) return; // doar perechi i<j
        const source = prev[from]?.[to];
        const target = next[to]?.[from];
        if (!source || !target) return;

        // Copiem Tur → Retur
        target.r_price = source.price;             // T devine R
        target.r_price_return = source.price_return; // T/R devine R/T
      });
    });
    return next;
  });
};

// Copiază toate valorile din triunghiul de jos (B→A) în triunghiul de sus (A→B)
const handleCopyReturnToOutbound = () => {
  if (!stations.length) return;
  setGrid((prev) => {
    const next = cloneGrid(prev);
    stations.forEach((from, i) => {
      stations.forEach((to, j) => {
        if (j <= i) return;
        const source = prev[to]?.[from];
        const target = next[from]?.[to];
        if (!source || !target) return;

        // Copiem Retur → Tur
        target.price = source.r_price;             // R devine T
        target.price_return = source.r_price_return; // R/T devine T/R
      });
    });
    return next;
  });
};

  return (
    <div className="space-y-4 max-w-full">
      <div className="grid grid-cols-2 gap-x-6 gap-y-2 w-fit text-sm">
        <div className="flex flex-col">
          <label className="text-xs text-gray-700 font-semibold">Traseu:</label>
          <select
            value={selectedRoute}
            onChange={(e) => setSelectedRoute(e.target.value)}
            className="border border-gray-300 rounded px-2 py-1 w-[200px]"
          >
            <option value="">Selectează traseu</option>
            {routes.map((route) => (
              <option key={route.id} value={route.id}>
                {route.name}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col">
          <label className="text-xs text-gray-700 font-semibold">Categorie:</label>
          <select
            value={selectedCategory}
            onChange={(e) => setSelectedCategory(e.target.value)}
            className="border border-gray-300 rounded px-2 py-1 w-[200px]"
          >
            <option value="">Selectează categorie</option>
            {categories.map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col">
          <label className="text-xs text-gray-700 font-semibold">Dată aplicare:</label>
          <input
            type="date"
            value={effectiveDate}
            onChange={(e) => setEffectiveDate(e.target.value)}
            className="border border-gray-300 rounded px-2 py-1 w-[200px]"
          />
        </div>
        <div className="flex flex-col">
          <label className="text-xs text-gray-700 font-semibold">Versiune:</label>
          <select
            value={selectedVersion}
            onChange={(e) => setSelectedVersion(e.target.value)}
            className="border border-gray-300 rounded px-2 py-1 w-[200px]"
          >
            <option value="">Selectează versiune</option>
            {versions.map((version) => (
              <option key={version.id} value={version.id}>
                {new Date(version.effective_from).toLocaleDateString()} (ver. {version.version})
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="flex space-x-2">
        <button
          type="button"
          onClick={handleCopyOutboundToReturn}
          className="px-2 py-1 bg-indigo-600 hover:bg-indigo-700 text-white rounded"
        >
          Copie Tur/Retur
        </button>
        <button
          type="button"
          onClick={handleCopyReturnToOutbound}
          className="px-2 py-1 bg-indigo-600 hover:bg-indigo-700 text-white rounded"
        >
          Copie Retur/Tur
        </button>
        <button
          type="button"
          onClick={handleSave}
          className="px-2 py-1 bg-blue-600 hover:bg-blue-700 text-white rounded"
        >
          Salvează
        </button>
      </div>

      {stations.length > 0 && (
        <div className="inline-block border rounded shadow bg-white p-2">
          <table className="table-fixed border-collapse text-[13px]">
            <thead className="sticky top-0 bg-gray-100 z-10">
              <tr>
                <th className="border px-1 py-1 text-center w-[90px] h-[50px]">Stație</th>
                {stations.map((station) => (
                  <th key={station} className="border px-1 py-1 text-center w-[70px] h-[32px] truncate">
                    {station}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {loadingItems ? (
                <tr>
                  <td colSpan={stations.length + 1} className="border px-1 py-1 text-center">
                    Se încarcă prețurile…
                  </td>
                </tr>
              ) : (
                stations.map((from, i) => (
                  <tr key={from} className={i % 2 === 0 ? 'bg-white' : 'bg-gray-100'}>
                    <td className="border px-1 py-1 text-black font-bold text-center w-[64px] h-[32px] align-middle">
                      {from}
                    </td>
                    {stations.map((to, j) => {
                      if (j === i) {
                        return (
                          <td
                            key={`${from}-${to}`}
                            className="border px-1 py-1 text-center w-[64px] h-[32px] align-middle bg-gray-100"
                          >
                            <div className="w-full h-[50px]" />
                          </td>
                        );
                      }

                      const cell = grid[from]?.[to];

                      if (j > i) {
                        return (
                          <td
                            key={`${from}-${to}`}
                            className="border px-1 py-1 text-center w-[64px] h-[32px] align-middle"
                          >
                            <div className="flex flex-col items-stretch gap-[4px]">
                              <span className="text-[10px] font-semibold uppercase text-gray-600 text-center">Tur</span>
                              <div className="flex items-center gap-[4px]">
                                <label className="w-[20px] text-[9px] font-medium text-gray-600 text-center">T</label>
                                <input
                                  className={[
                                    'w-[46px] h-[20px] px-1 text-[13px]',
                                    'border border-gray-300 rounded text-center',
                                    'focus:outline-none',
                                  ].join(' ')}
                                  value={cell?.price ?? ''}
                                  onChange={(e) => handleCellChange(from, to, 'price', e.target.value)}
                                />
                              </div>
                              <div className="flex items-center gap-[4px]">
                                <label className="w-[20px] text-[9px] font-medium text-gray-600 text-center">T/R</label>
                                <input
                                  className={[
                                    'w-[46px] h-[20px] px-1 text-[13px]',
                                    'border border-gray-300 rounded text-center',
                                    'focus:outline-none',
                                  ].join(' ')}
                                  value={cell?.price_return ?? ''}
                                  onChange={(e) => handleCellChange(from, to, 'price_return', e.target.value)}
                                />
                              </div>
                            </div>
                          </td>
                        );
                      }


                      // j < i → TRIUNGHIUL DE JOS: editezi câmpurile LOCALE de retur pentru [from][to]
                      const cellDown = grid[from]?.[to];
                     return (
                        <td key={`${from}-${to}`} className="border px-1 py-1 text-center w-[64px] h-[32px] align-middle">
                          <div className="flex flex-col items-stretch gap-[4px]">
                            <span className="text-[10px] font-semibold uppercase text-gray-600 text-center">Retur</span>
                            <div className="flex items-center gap-[4px]">
                              <label className="w-[20px] text-[9px] font-medium text-gray-600 text-center">R</label>
                              <input
                                className="w-[46px] h-[20px] px-1 text-[13px] border border-gray-300 rounded text-center focus:outline-none"
                                value={cellDown?.r_price ?? ''}
                                onChange={(e) => handleCellChange(from, to, 'r_price', e.target.value)}
                              />
                            </div>
                            <div className="flex items-center gap-[4px]">
                              <label className="w-[20px] text-[9px] font-medium text-gray-600 text-center">R/T</label>
                              <input
                                className="w-[46px] h-[20px] px-1 text-[13px] border border-gray-300 rounded text-center focus:outline-none"
                                value={cellDown?.r_price_return ?? ''}
                                onChange={(e) => handleCellChange(from, to, 'r_price_return', e.target.value)}
                             />
                            </div>
                          </div>
                        </td>
                      );

                    })}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}