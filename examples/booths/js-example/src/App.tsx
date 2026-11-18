import React, { useEffect, useMemo, useState } from 'react';

type ServerTime = {
  iso: string;
  epochMs: number;
  locale: string;
};

function format(dt: Date) {
  return dt.toLocaleString();
}

export default function App() {
  const [serverTime, setServerTime] = useState<ServerTime | null>(null);
  const [clientNow, setClientNow] = useState<Date>(new Date());
  const [error, setError] = useState<string | null>(null);

  // Tick client time every 250ms for smoothness
  useEffect(() => {
    const id = setInterval(() => setClientNow(new Date()), 250);
    return () => clearInterval(id);
  }, []);

  // Fetch server time
  const fetchServerTime = async () => {
    try {
      setError(null);
      const res = await fetch('/api/currenttime');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data: ServerTime = await res.json();
      setServerTime(data);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
    }
  };

  useEffect(() => {
    fetchServerTime();
    const id = setInterval(fetchServerTime, 1000);
    return () => clearInterval(id);
  }, []);

  const serverDate = useMemo(() => (serverTime ? new Date(serverTime.epochMs) : null), [serverTime]);

  return (
    <div className="app">
      <h1>Time App</h1>
      <div className="cards">
        <div className="card time-card">
          <h2>Client Time</h2>
          <p className="time">{format(clientNow)}</p>
          <p className="sub">ISO: {clientNow.toISOString()}</p>
        </div>
        <div className="card time-card">
          <h2>Server Time</h2>
          {serverDate ? (
            <>
              <p className="time">{format(serverDate)}</p>
              <p className="sub">ISO: {serverDate.toISOString()}</p>
            </>
          ) : (
            <p>Loading…</p>
          )}
          {error && <p className="err">Failed to fetch: {error}</p>}
        </div>
      </div>
    </div>
  );
}
