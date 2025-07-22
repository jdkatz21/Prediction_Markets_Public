import React from 'react';


export default function CustomTooltip({ payload, label }) {
  if (!payload || !payload.length) return null;

  return (
    <div className="w-60 bg-white border border-gray-300 p-3 rounded shadow text-sm z-10 pointer-events-none">

      <p className="font-semibold mb-1">Strike: {label.toFixed(2)}%</p>

      {payload.map((entry, index) => (
        <p
          key={index}
          className="truncate"
          style={{
            color: entry.color,
            whiteSpace: 'nowrap',
          }}
        >
          {entry.name}: {entry.value.toFixed(1)}%
        </p>
      ))}
    </div>
  );
}
