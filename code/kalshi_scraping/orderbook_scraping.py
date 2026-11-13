import requests, time, csv, datetime as dt

BASE = "https://api.elections.kalshi.com/trade-api/v2"
SERIES_LIST = ["KXCPIYOY"]  # both old and new CPI series
PERIOD = 1440  # daily
ROWS = []

# Time range
start_ts = int(dt.datetime(2022, 1, 1, tzinfo=dt.timezone.utc).timestamp())
end_ts   = int(dt.datetime(2025, 12, 31, tzinfo=dt.timezone.utc).timestamp())


def get_all_markets(series_ticker):
    """Fetch all markets for a series using proper pagination (cursor)."""
    print(f"\n=== Fetching all markets for {series_ticker} ===")
    markets = []
    cursor = None

    while True:
        params = {"series_ticker": series_ticker, "limit": 1000}
        if cursor:
            params["cursor"] = cursor
        url = f"{BASE}/markets"
        resp = requests.get(url, params=params)
        try:
            data = resp.json()
        except Exception:
            print("⚠️ JSON decode error:", resp.text[:200])
            break

        batch = data.get("markets", [])
        if not batch:
            break

        markets.extend(batch)
        print(f"  Retrieved {len(batch)} markets (total {len(markets)})")

        cursor = data.get("cursor")  # <-- this key contains the next page token
        if not cursor:
            break

        time.sleep(0.25)  # polite delay

    print(f"✅ Retrieved {len(markets)} total markets for {series_ticker}")
    return markets

get_all_markets('KXCPI')
def fetch_candles(series, ticker):
    """Fetch daily candlestick data for one market."""
    url = f"{BASE}/series/{series}/markets/{ticker}/candlesticks"
    params = {"start_ts": start_ts, "end_ts": end_ts, "period_interval": PERIOD}
    res = requests.get(url, params=params)
    try:
        return res.json().get("candlesticks", [])
    except Exception:
        return []


# --- main loop ---
for SERIES in SERIES_LIST:
    all_markets = get_all_markets(SERIES)

    for m in all_markets:
        ticker = m.get("ticker")
        event_ticker = m.get("event_ticker")
        if not ticker:
            continue

        print(f"→ Fetching {ticker}")
        candles = fetch_candles(SERIES, ticker)

        for c in candles:
            ts = c["end_period_ts"]
            dt_utc = dt.datetime.utcfromtimestamp(ts).isoformat() + "Z"
            ROWS.append({
                "series": SERIES,
                "event_ticker": event_ticker,
                "market_ticker": ticker,
                "end_period_utc": dt_utc,
                "yes_bid_open":  c["yes_bid"]["open"],
                "yes_bid_high":  c["yes_bid"]["high"],
                "yes_bid_low":   c["yes_bid"]["low"],
                "yes_bid_close": c["yes_bid"]["close"],
                "yes_ask_open":  c["yes_ask"]["open"],
                "yes_ask_high":  c["yes_ask"]["high"],
                "yes_ask_low":   c["yes_ask"]["low"],
                "yes_ask_close": c["yes_ask"]["close"],
                "price_open":    c["price"]["open"],
                "price_high":    c["price"]["high"],
                "price_low":     c["price"]["low"],
                "price_close":   c["price"]["close"],
                "volume":        c.get("volume"),
                "open_interest": c.get("open_interest"),
            })

        time.sleep(0.25)


# Save results
if ROWS:
    outfile = "data/orderbook_data/daily_bid_ask_cpi_data.csv"
    with open(outfile, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=ROWS[0].keys())
        w.writeheader()
        w.writerows(ROWS)
    print(f"\n✅ Wrote {len(ROWS)} rows to {outfile}")
else:
    print("⚠️ No rows written; check API connectivity or parameters.")
