import React from 'react';

export default function CustomTooltip({ payload, label }) {
  if (!payload || !payload.length || label == null) return null;

  return (
    <div className="w-60 bg-white border border-gray-300 p-3 rounded shadow text-sm z-10 pointer-events-none">
      <p className="font-semibold mb-1">
        Strike: {typeof label === 'number' ? label.toFixed(2) + '%' : '—'}
      </p>

      {payload.map((entry, index) => {
        const value = entry?.value;
        return (
          <p
            key={index}
            className="truncate"
            style={{
              color: entry?.color || '#000',
              whiteSpace: 'nowrap',
            }}
          >
            {entry?.name ?? '—'}: {typeof value === 'number' ? value.toFixed(1) + '%' : '—'}
          </p>
        );
      })}
    </div>
  );
}
