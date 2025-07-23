import React, { useEffect, useState, useRef } from 'react';
import axios from 'axios';
import {
  ResponsiveContainer, BarChart, Bar, XAxis, YAxis,
  CartesianGrid, Tooltip, Legend
} from 'recharts';
import CustomTooltip from './CustomTooltip';
import AnimatedBar from './AnimatedBar';


// const API = 'https://prediction-markets-public-1.onrender.com:';
const API = 'http://localhost:8000';


function createBinLabels(strikes, smallestBin, largestBin, type) {
  const increment = type === "headline_cpi_releases" | type === "unemployment_releases" ? 0.1 : 0.25;

  return strikes.map((s, i) => {
    const rounded = (val) => parseFloat((Math.round(val * 100) / 100).toFixed(2));

    if (smallestBin !== '' && s === Math.min(...strikes)) {
      return `\n<= ${rounded(s + increment).toFixed(2)}`;
    } else if (largestBin !== '' && s === Math.max(...strikes)) {
      return `\n> ${rounded(s).toFixed(2)}`;
    } else {
      return `${rounded(s).toFixed(2)}-\n${rounded(s + increment).toFixed(2)}`;
    }
  });
}




export default function App() {
  const [contracts, setContracts] = useState([]);
  const [types, setTypes] = useState([]);

  const [selectedType, setSelectedType] = useState('');
  const [selectedContract, setSelectedContract] = useState('');
  const [date1, setDate1] = useState('2025-07-01');
  const [date2, setDate2] = useState('2025-07-15');

  const [smallestBin, setSmallestBin] = useState('');
  const [largestBin, setLargestBin] = useState('');

  const [chartData, setChartData] = useState([]);
  const [noData1, setNoData1] = useState(false);
  const [noData2, setNoData2] = useState(false);
  const [loading, setLoading] = useState(false);

  const [availableDates, setAvailableDates] = useState([]);

  const containerRef = useRef(null);
  const [tickFontSize, setTickFontSize] = useState(12);


  const marketPaths = {
    fed_levels: '/kxfed/fed-funds-rate',
    headline_cpi_releases: '/kxcpiyoy/inflation',
    unemployment_releases: '/kxu3/unemployment'
    // Add more types as needed
  };

  const marketPath = selectedType && marketPaths[selectedType] ? marketPaths[selectedType] : 'kxfed/fed-funds-rate';

  // ========== API Helpers ==========

  const formatPrettyDate = (isoDate) => {
    if (!isoDate) return '—';
    const [year, month, day] = isoDate.split('-').map(Number);
    const localDate = new Date(year, month - 1, day);
    return localDate.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  };

  const fetchTypes = async () => {
    try {
      const { data } = await axios.get(`${API}/types`);
      setTypes(data.types);
      if (data.types.length) setSelectedType(data.types[0]);
    } catch (err) {
      console.error('Failed to fetch types', err);
    }
  };

  const fetchContracts = async (type) => {
    try {
      const { data } = await axios.get(`${API}/contracts`, { params: { type } });
      setContracts(data.contracts);
      if (data.contracts.length) setSelectedContract(data.contracts[0]);
    } catch (err) {
      console.error('Failed to fetch contracts', err);
    }
  };

  const fetchContractInfo = async (contract) => {
    try {
      const { data } = await axios.get(`${API}/contract-info`, {
        params: { contract_preamble: contract }
      });
      if (data.previous_horizon_date) setDate1(data.previous_horizon_date);
      if (data.latest_prediction_date) setDate2(data.latest_prediction_date);
    } catch (err) {
      console.error('Failed to fetch contract info', err);
    }
  };

  const fetchDistribution = async () => {
  if (!selectedContract || !date1 || !date2) return;

  const params = new URLSearchParams({
    contract_preamble: selectedContract,
    prediction_dates: date1,
  });
  params.append('prediction_dates', date2);
  if (smallestBin) params.append('smallest_bin', smallestBin);
  if (largestBin) params.append('largest_bin', largestBin);

  // 👇 Don't clear chartData immediately — leave it during fetch
  setLoading(true);
  try {
    const { data } = await axios.get(`${API}/distribution?${params.toString()}`);

    const data1 = data.data[date1] || [];
    const data2 = data.data[date2] || [];

    const map1 = Object.fromEntries(data1.map(d => [d.strike, d.probability]));
    const map2 = Object.fromEntries(data2.map(d => [d.strike, d.probability]));
    const allStrikes = Array.from(new Set([...data1, ...data2].map(d => d.strike))).sort((a, b) => a - b);

    const merged = allStrikes.map(strike => ({
      strike,
      [date1]: map1[strike] || 0,
      [date2]: map2[strike] || 0,
    }));

    // ✅ Replace only after fetch is successful
    setChartData(merged);
    setNoData1(!data1.some(d => d.probability > 0));
    setNoData2(!data2.some(d => d.probability > 0));
  } catch (err) {
    console.error('Error fetching distribution:', err);
    // Optional: keep old chartData instead of clearing
    // setChartData([]);
    setNoData1(true);
    setNoData2(true);
  } finally {
    setLoading(false);
  }
};


  const fetchAvailableDates = async (contract) => {
    if (!contract || !selectedType) return;

    try {
      const { data } = await axios.get(`${API}/prediction-dates`, {
        params: { contract_preamble: contract, type: selectedType }
      });
      const sorted = data.dates.sort();
      setAvailableDates(sorted);
    } catch (err) {
      console.error('Failed to fetch prediction dates', err);
      setAvailableDates([]);
    }
    console.log("Fetching dates with:", { contract_preamble: contract, type: selectedType });

  };

  // ========== Effects ==========

  useEffect(() => {
    fetchTypes();
  }, []);

  useEffect(() => {
    if (selectedType) fetchContracts(selectedType);
  }, [selectedType]);

  useEffect(() => {
    if (selectedContract) fetchContractInfo(selectedContract);
  }, [selectedContract]);

  useEffect(() => {
    fetchDistribution();
  }, [selectedContract, date1, date2, smallestBin, largestBin]);

  useEffect(() => {
      if (selectedContract) {
        fetchContractInfo(selectedContract);
        fetchAvailableDates(selectedContract);
      }
    }, [selectedContract]);

    useEffect(() => {
      console.log("Available Dates:", availableDates);
    }, [availableDates]);


    useEffect(() => {
      const observer = new ResizeObserver(([entry]) => {
        const width = entry.contentRect.width;

        if (width < 400) {
          setTickFontSize(8);
        } else if (width < 600) {
          setTickFontSize(10);
        } else {
          setTickFontSize(12);
        }
      });

      if (containerRef.current) {
        observer.observe(containerRef.current);
      }

      return () => observer.disconnect();
    }, []);


  // ========== Render ==========

  return (

    
  <div className="p-6 max-w-6xl mx-auto text-gray-800">

    <h1 className="text-3xl font-bold mb-6 text-center">Kalshi Distribution Viewer</h1>

    <div className="bg-white rounded-xl shadow-md p-6 space-y-6 border border-gray-200">
      {/* Selection Controls */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">


        <div>
          <label className="block text-sm font-medium mb-1">Contract Type</label>
          <select
            value={selectedType}
            onChange={e => setSelectedType(e.target.value)}
            className="border border-gray-300 rounded px-3 py-2 w-full shadow-sm focus:ring-blue-500 focus:border-blue-500"
          >
            {types.map(t => <option key={t} value={t}>{t}</option>)}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Contract Preamble</label>
          <select
            value={selectedContract}
            onChange={e => setSelectedContract(e.target.value)}
            className="border border-gray-300 rounded px-3 py-2 w-full shadow-sm focus:ring-blue-500 focus:border-blue-500"
          >
            {contracts.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>

          {/* Comparison date */}
         {availableDates.length > 0 && (
            <div className="mt-4">
              <label className="block text-sm font-medium mb-1">
                Date of prediction: {formatPrettyDate(date1)}
              </label>
              <input
                type="range"
                min={0}
                max={availableDates.length - 1}
                value={Math.max(0, availableDates.findIndex(d => d === date1))}

                onChange={(e) => setDate1(availableDates[+e.target.value])}
                className="w-full"
              />
            </div>
          )}

        <div>
          <label className="block text-sm font-medium mb-1">Comparison Date</label>
          <input
            type="date"
            value={date2}
            onChange={e => setDate2(e.target.value)}
            className="border border-gray-300 rounded px-3 py-2 w-full shadow-sm focus:ring-blue-500 focus:border-blue-500"
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Min Bin (optional)</label>
          <input
            type="number"
            value={smallestBin}
            onChange={e => setSmallestBin(e.target.value)}
            className="border border-gray-300 rounded px-3 py-2 w-full shadow-sm focus:ring-blue-500 focus:border-blue-500"
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Max Bin (optional)</label>
          <input
            type="number"
            value={largestBin}
            onChange={e => setLargestBin(e.target.value)}
            className="border border-gray-300 rounded px-3 py-2 w-full shadow-sm focus:ring-blue-500 focus:border-blue-500"
          />
        </div>

      
      </div>

    

      {/* Chart */}
      <div className="mt-6" ref={containerRef}>
        <ResponsiveContainer width="100%" height={400}>
          <BarChart data={chartData} margin={{ top: 20, right: 30, left: 10, bottom: 20 }}>
            <CartesianGrid strokeDasharray="3 3" />
            {/* <XAxis dataKey="strike" label={{ value: 'Rate Strike', position: 'insideBottom', offset: -5 }} /> */}

           

            <XAxis
              dataKey="strike"
              tickFormatter={(val) => {
                const labels = createBinLabels(
                  chartData.map((d) => d.strike),
                  smallestBin,
                  largestBin,
                  selectedType
                );
                const idx = chartData.findIndex((d) => d.strike === val);
                return labels[idx] || val;
              }}
              tick={{ fontSize: tickFontSize }}
              label={{ value: 'Range', position: 'insideBottom', dy: 10 }}
            />



            <YAxis label={{ value: 'Probability (%)', angle: -90, position: 'insideLeft' }} domain={[0, 100]} />

            <Tooltip 
              content={<CustomTooltip />} 
              position={{ x: 200, y: 20 }} 
              isAnimationActive={false}
            />
            <Legend layout="vertical" verticalAlign="top" align="left" />
         

              <Bar
                dataKey={date1}
                name={formatPrettyDate(date1)}
                fill="#3B82F6"
                shape={<AnimatedBar />}
              />
              <Bar
                dataKey={date2}
                name={formatPrettyDate(date2)}
                fill="#EF4444"
                shape={<AnimatedBar />}
              />

          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* No Data Warning */}
      {!loading && chartData.length > 0 && (
        <div className="text-sm text-red-600 space-y-1">
          {noData1 && <p>No data found for Prediction Date 1: {date1}</p>}
          {noData2 && <p>No data found for Prediction Date 2: {date2}</p>}
        </div>
      )}

      {/* Footer */}
      {selectedContract && (
        <div className="mt-6 text-sm text-gray-600 space-y-2 border-t pt-4">
         
          <p>
            View this contract on{' '}
            <a
              href={`https://kalshi.com/markets/${marketPath}#${selectedContract.toLowerCase()}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-600 hover:underline"
            >
              Kalshi ({selectedContract})
            </a>.
          </p>
          
          <p>
            Each bar represents an outcome between the listed strike and the next (higher) strike.
          </p>
          <p>
            Please cite Diercks, Katz (2025). Source on{' '}
            <a
              href="https://github.com/jdkatz21/Prediction_Markets_Public"
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-600 hover:underline"
            >
              GitHub
            </a>.
          </p>

          <p>
            Made by Jared Dean Katz{' '}
            <a
              href="https://jareddeankatz.com"
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-600 hover:underline"
            >
              @jareddeankatz.com
            </a>.
          </p>

        </div>
      )}
    </div>
  </div>
);



}