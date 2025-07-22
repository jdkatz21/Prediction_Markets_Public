// App.jsx
import React, { useEffect, useState, useCallback } from 'react';
import axios from 'axios';
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip as ReTooltip,
  Legend,
} from 'recharts';
import CustomTooltip from './CustomTooltip';

const API = 'http://localhost:8000';

// Small utility: null-safe percent format
const fmtPct = (v) => (v == null ? '–' : `${v.toFixed(1)}%`);

export default function App() {
  // ------- Data State -------
  const [types, setTypes] = useState([]);
  const [contracts, setContracts] = useState([]);
  const [selectedType, setSelectedType] = useState('');
  const [selectedContract, setSelectedContract] = useState('');

  // Dates default; backend will overwrite on contract change
  const [date1, setDate1] = useState('2025-07-01');
  const [date2, setDate2] = useState('2025-07-15');

  // Contract meta fetched via /contract-info
  const [contractInfo, setContractInfo] = useState({
    horizon_date: null,
    previous_horizon_date: null,
    latest_prediction_date: null,
  });

  // Bin range
  const [smallestBin, setSmallestBin] = useState('');
  const [largestBin, setLargestBin] = useState('');

  // Chart + status
  const [chartData, setChartData] = useState([]);
  const [noData1, setNoData1] = useState(false);
  const [noData2, setNoData2] = useState(false);
  const [loading, setLoading] = useState(false);

  // State used for fixed overlay tooltip (if you still want the pinned TL box)
  const [tooltipPayload, setTooltipPayload] = useState(null);
  const [tooltipLabel, setTooltipLabel] = useState(null);

  // ------- API Calls -------

  const fetchTypes = useCallback(async () => {
    try {
      const { data } = await axios.get(`${API}/types`);
      setTypes(data.types);
      if (data.types.length) setSelectedType(data.types[0]);
    } catch (err) {
      console.error('Failed to fetch types', err);
    }
  }, []);

  const fetchContracts = useCallback(async (type) => {
    try {
      const { data } = await axios.get(`${API}/contracts`, { params: { type } });
      setContracts(data.contracts);
      if (data.contracts.length) setSelectedContract(data.contracts[0]);
    } catch (err) {
      console.error('Failed to fetch contracts', err);
    }
  }, []);

  const fetchContractInfo = useCallback(async (contract) => {
    try {
      const { data } = await axios.get(`${API}/contract-info`, {
        params: { contract_preamble: contract },
      });

      setContractInfo(data || {});

      // Auto-set date1/date2 from backend suggestions (if provided)
      if (data.previous_horizon_date) setDate1(data.previous_horizon_date);
      if (data.latest_prediction_date) setDate2(data.latest_prediction_date);
    } catch (err) {
      console.error('Failed to fetch contract info', err);
    }
  }, []);

  const fetchDistribution = useCallback(async () => {
    if (!selectedContract || !date1 || !date2) return;

    const params = new URLSearchParams({
      contract_preamble: selectedContract,
      prediction_dates: date1,
    });
    params.append('prediction_dates', date2);
    if (smallestBin !== '') params.append('smallest_bin', smallestBin);
    if (largestBin !== '') params.append('largest_bin', largestBin);

    setLoading(true);
    try {
      const { data } = await axios.get(`${API}/distribution?${params.toString()}`);
      const data1 = data.data[date1] || [];
      const data2 = data.data[date2] || [];

      const map1 = Object.fromEntries(data1.map((d) => [d.strike, d.probability]));
      const map2 = Object.fromEntries(data2.map((d) => [d.strike, d.probability]));

      const allStrikes = Array.from(
        new Set([...data1, ...data2].map((d) => d.strike))
      ).sort((a, b) => a - b);

      const merged = allStrikes.map((strike) => ({
        strike,
        [date1]: map1[strike] || 0,
        [date2]: map2[strike] || 0,
      }));

      setChartData(merged);
      setNoData1(!data1.some((d) => d.probability > 0));
      setNoData2(!data2.some((d) => d.probability > 0));
    } catch (err) {
      console.error('Error fetching distribution:', err);
      setChartData([]);
      setNoData1(true);
      setNoData2(true);
    } finally {
      setLoading(false);
    }
  }, [selectedContract, date1, date2, smallestBin, largestBin]);

  // ------- Effects -------
  useEffect(() => {
    fetchTypes();
  }, [fetchTypes]);

  useEffect(() => {
    if (selectedType) fetchContracts(selectedType);
  }, [selectedType, fetchContracts]);

  useEffect(() => {
    if (selectedContract) fetchContractInfo(selectedContract);
  }, [selectedContract, fetchContractInfo]);

  useEffect(() => {
    fetchDistribution();
  }, [fetchDistribution]);

  // ------- UI Helpers -------

  const swapDates = () => {
    setDate1(date2);
    setDate2(date1);
  };

  const resetBins = () => {
    setSmallestBin('');
    setLargestBin('');
  };

  // Example: show suggestion buttons for backend-suggested dates
  const applySuggestedDates = () => {
    if (contractInfo.previous_horizon_date) {
      setDate1(contractInfo.previous_horizon_date);
    }
    if (contractInfo.latest_prediction_date) {
      setDate2(contractInfo.latest_prediction_date);
    }
  };

  const horizonText = contractInfo?.horizon_date
    ? new Date(contractInfo.horizon_date).toLocaleDateString()
    : '—';

  // ------- Render -------

  return (
    <div className="min-h-screen w-full bg-gray-50 text-gray-900">
      <header className="w-full bg-white shadow-sm mb-8">
        <div className="max-w-6xl mx-auto px-4 py-4">
          <h1 className="text-2xl font-bold tracking-tight">Kalshi Distribution Viewer</h1>
          <p className="text-sm text-gray-600 mt-1">
            Visualize market-implied probabilities across Kalshi interest rate and macro releases.
          </p>
        </div>
      </header>

      <main className="max-w-6xl mx-auto px-4 pb-16 grid gap-8 lg:grid-cols-[320px_1fr]">
        {/* -------- Control Panel -------- */}
        <aside className="lg:sticky lg:top-4 self-start">
          <div className="bg-white border border-gray-200 rounded-lg shadow-sm p-4 space-y-4">
            <h2 className="font-semibold text-gray-800 text-lg">Controls</h2>

            {/* Contract Type */}
            <div>
              <label htmlFor="contractType" className="block text-sm font-medium">
                Contract Type
              </label>
              <select
                id="contractType"
                value={selectedType}
                onChange={(e) => setSelectedType(e.target.value)}
                className="mt-1 block w-full rounded border-gray-300 text-sm"
              >
                {types.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
            </div>

            {/* Contract Preamble */}
            <div>
              <label htmlFor="contractPreamble" className="block text-sm font-medium">
                Contract Preamble
              </label>
              <select
                id="contractPreamble"
                value={selectedContract}
                onChange={(e) => setSelectedContract(e.target.value)}
                className="mt-1 block w-full rounded border-gray-300 text-sm"
              >
                {contracts.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </div>

            {/* Suggested Dates summary */}
            <div className="text-xs text-gray-500 bg-gray-100 rounded p-2 leading-relaxed">
              <p>
                Horizon:{' '}
                <span className="font-medium text-gray-700">{horizonText}</span>
              </p>
              {contractInfo.previous_horizon_date && (
                <p>Prev horizon: {contractInfo.previous_horizon_date}</p>
              )}
              {contractInfo.latest_prediction_date && (
                <p>Latest pred: {contractInfo.latest_prediction_date}</p>
              )}
              {(contractInfo.previous_horizon_date ||
                contractInfo.latest_prediction_date) && (
                <button
                  type="button"
                  onClick={applySuggestedDates}
                  className="mt-1 text-blue-600 hover:underline"
                >
                  Apply suggested dates
                </button>
              )}
            </div>

            {/* Prediction Dates */}
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label
                  htmlFor="predictionDate1"
                  className="block text-xs font-medium text-gray-700"
                >
                  Prediction Date 1
                </label>
                <input
                  id="predictionDate1"
                  type="date"
                  value={date1}
                  onChange={(e) => setDate1(e.target.value)}
                  className="mt-1 block w-full rounded border-gray-300 text-sm"
                />
              </div>
              <div>
                <label
                  htmlFor="predictionDate2"
                  className="block text-xs font-medium text-gray-700"
                >
                  Prediction Date 2
                </label>
                <input
                  id="predictionDate2"
                  type="date"
                  value={date2}
                  onChange={(e) => setDate2(e.target.value)}
                  className="mt-1 block w-full rounded border-gray-300 text-sm"
                />
              </div>
            </div>

            {/* Swap Dates */}
            <button
              type="button"
              onClick={swapDates}
              className="w-full py-1.5 text-sm rounded bg-gray-200 hover:bg-gray-300 transition"
            >
              Swap Dates
            </button>

            {/* Bin Controls */}
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label
                  htmlFor="smallestBin"
                  className="block text-xs font-medium text-gray-700"
                >
                  Min Bin
                </label>
                <input
                  id="smallestBin"
                  type="number"
                  value={smallestBin}
                  onChange={(e) => setSmallestBin(e.target.value)}
                  className="mt-1 block w-full rounded border-gray-300 text-sm"
                  placeholder="(auto)"
                />
              </div>
              <div>
                <label
                  htmlFor="largestBin"
                  className="block text-xs font-medium text-gray-700"
                >
                  Max Bin
                </label>
                <input
                  id="largestBin"
                  type="number"
                  value={largestBin}
                  onChange={(e) => setLargestBin(e.target.value)}
                  className="mt-1 block w-full rounded border-gray-300 text-sm"
                  placeholder="(auto)"
                />
              </div>
            </div>

            {/* Reset Bins */}
            <button
              type="button"
              onClick={resetBins}
              className="w-full py-1.5 text-sm rounded bg-gray-200 hover:bg-gray-300 transition"
            >
              Reset Bins
            </button>
          </div>
        </aside>

        {/* -------- Chart & Explanatory Text -------- */}
        <section className="space-y-6">
          {/* Chart Card */}
          <div className="bg-white border border-gray-200 rounded-lg shadow-sm p-4">
            <h2 className="font-semibold mb-2 text-gray-800 text-lg">
              Probability Distribution
            </h2>
            <p className="text-xs text-gray-500 mb-4">
              Comparing market-implied distributions between two prediction dates.
            </p>

            <div className="relative w-full h-[400px]">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart
                  data={chartData}
                  margin={{ top: 20, right: 30, left: 10, bottom: 5 }}
                >
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis
                    dataKey="strike"
                    label={{
                      value: 'Rate Strike',
                      position: 'insideBottom',
                      offset: -5,
                    }}
                  />
                  <YAxis
                    label={{
                      value: 'Probability (%)',
                      angle: -90,
                      position: 'insideLeft',
                    }}
                    domain={[0, 100]}
                  />
                  <ReTooltip
                    cursor={{ fill: 'transparent' }}
                    content={({ payload, label, active }) => {
                      if (active) {
                        setTooltipPayload(payload);
                        setTooltipLabel(label);
                      }
                      return null;
                    }}
                  />
                  <Legend layout="horizontal" verticalAlign="top" align="center" />
                  <Bar dataKey={date1} fill="blue" />
                  <Bar dataKey={date2} fill="red" />
                </BarChart>
              </ResponsiveContainer>

              {/* Fixed overlay tooltip (top-left of plotting area) */}
              {tooltipPayload && tooltipLabel && (
                <CustomTooltip payload={tooltipPayload} label={tooltipLabel} />
              )}
            </div>

            {!loading && chartData.length > 0 && (
              <div className="mt-2 text-sm text-red-600 space-y-1">
                {noData1 && <p>No data found for Prediction Date 1: {date1}</p>}
                {noData2 && <p>No data found for Prediction Date 2: {date2}</p>}
              </div>
            )}
          </div>

          {/* Info Card */}
          {selectedContract && (
            <div className="bg-white border border-gray-200 rounded-lg shadow-sm p-4 text-sm leading-relaxed text-gray-700 space-y-2">
              <p>
                View this contract on{' '}
                <a
                  href={`https://kalshi.com/markets/kxfed/fed-funds-rate#${selectedContract.toLowerCase()}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-600 underline"
                >
                  Kalshi ({selectedContract})
                </a>
                .
              </p>
              <p>
                Each bar represents a bin (or “strike”) for a possible target federal funds rate.
                Kalshi bins are usually spaced 25 basis points apart and a strike implies the lower
                bound of the target range will lie at that strike. A 50% probability at strike 4.00
                suggests a 50% chance the FOMC sets the range to 4.00–4.25%.
              </p>
              <hr className="my-2" />
              <p className="text-xs text-gray-500">
                Please cite Diercks, Katz (2025). Source code & raw data on{' '}
                <a
                  href="https://github.com/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-600 underline"
                >
                  GitHub
                </a>
                .
              </p>
            </div>
          )}
        </section>
      </main>
    </div>
  );
}
