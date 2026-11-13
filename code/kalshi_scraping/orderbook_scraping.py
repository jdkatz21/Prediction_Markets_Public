import requests, time, csv, datetime as dt
from tickers import autogenerate_kalshi_tickers

BASE = "https://api.elections.kalshi.com/trade-api/v2"
SERIES_LIST = ["KXU3"]
PERIOD = 1440  # daily

start_ts = int(dt.datetime(2022, 1, 1, tzinfo=dt.timezone.utc).timestamp())
end_ts   = int(dt.datetime(2026, 7, 1, tzinfo=dt.timezone.utc).timestamp())

ROWS = []


def _price_block(block):
    """
    Normalize a price sub-dict (yes_bid / yes_ask / price) from either
    endpoint shape into {"open","high","low","close"} in dollars (float).

    - live endpoint:       open_dollars / high_dollars / low_dollars / close_dollars (already floats)
    - historical endpoint: open / high / low / close, in cents (ints)
    """
    if block is None:
        return {"open": None, "high": None, "low": None, "close": None}

    if "open_dollars" in block:
        return {
            "open":  block.get("open_dollars"),
            "high":  block.get("high_dollars"),
            "low":   block.get("low_dollars"),
            "close": block.get("close_dollars"),
        }
    else:
        # cents -> dollars
        return {
            "open":  block.get("open")   if block.get("open")  is not None else None,
            "high":  block.get("high")   if block.get("high")  is not None else None,
            "low":   block.get("low")    if block.get("low")   is not None else None,
            "close": block.get("close")  if block.get("close") is not None else None,
        }


def normalize_candle(c):
    """Convert a raw candlestick (either endpoint's shape) into one canonical dict."""
    return {
        "end_period_ts": c["end_period_ts"],
        "yes_bid": _price_block(c.get("yes_bid")),
        "yes_ask": _price_block(c.get("yes_ask")),
        "price":   _price_block(c.get("price")),
        "volume":        c.get("volume_fp", c.get("volume")),
        "open_interest": c.get("open_interest_fp", c.get("open_interest")),
    }


def fetch_candles_historical(ticker):
    url = f"{BASE}/historical/markets/{ticker}/candlesticks"
    params = {"start_ts": start_ts, "end_ts": end_ts, "period_interval": PERIOD}
    resp = requests.get(url, params=params)
    try:
        return resp.json().get("candlesticks", [])
    except Exception:
        return []


def fetch_candles_live(series, ticker):
    url = f"{BASE}/series/{series}/markets/{ticker}/candlesticks"
    params = {"start_ts": start_ts, "end_ts": end_ts, "period_interval": PERIOD}
    resp = requests.get(url, params=params)
    try:
        return resp.json().get("candlesticks", [])
    except Exception:
        return []


def fetch_all_candles(series, ticker):
    """Fetch, normalize, and combine candlesticks from both endpoints, deduped on timestamp."""
    hist = [normalize_candle(c) for c in fetch_candles_historical(ticker)]
    live = [normalize_candle(c) for c in fetch_candles_live(series, ticker)]

    seen = set()
    combined = []
    for c in hist + live:
        ts = c["end_period_ts"]
        if ts not in seen:
            seen.add(ts)
            combined.append(c)

    combined.sort(key=lambda c: c["end_period_ts"])
    return combined


def parse_candle_row(series, event_ticker, ticker, c):
    """c is already normalized here, so this is just a flat re-key into CSV columns."""
    ts = c["end_period_ts"]
    dt_utc = dt.datetime.utcfromtimestamp(ts).isoformat() + "Z"
    return {
        "series":         series,
        "event_ticker":   event_ticker,
        "market_ticker":  ticker,
        "end_period_utc": dt_utc,
        "yes_bid_open":   c["yes_bid"]["open"],
        "yes_bid_high":   c["yes_bid"]["high"],
        "yes_bid_low":    c["yes_bid"]["low"],
        "yes_bid_close":  c["yes_bid"]["close"],
        "yes_ask_open":   c["yes_ask"]["open"],
        "yes_ask_high":   c["yes_ask"]["high"],
        "yes_ask_low":    c["yes_ask"]["low"],
        "yes_ask_close":  c["yes_ask"]["close"],
        "price_open":     c["price"]["open"],
        "price_high":     c["price"]["high"],
        "price_low":      c["price"]["low"],
        "price_close":    c["price"]["close"],
        "volume":         c["volume"],
        "open_interest":  c["open_interest"],
    }


for SERIES in SERIES_LIST:
    all_tickers = autogenerate_kalshi_tickers(SERIES)

    for ticker in all_tickers:
        print(f"→ Fetching {ticker}")
        candles = fetch_all_candles(SERIES, ticker)

        if not candles:
            print(f"  No candles for {ticker}, skipping")
            continue

        event_ticker = "-".join(ticker.split("-")[:2])

        for c in candles:
            ROWS.append(parse_candle_row(SERIES, event_ticker, ticker, c))

        print(f"  {len(candles)} candles")
        time.sleep(0.25)


if ROWS:
    outfile = "data/orderbook_data/daily_bid_ask_unemploymemt_data.csv"
    with open(outfile, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=ROWS[0].keys())
        w.writeheader()
        w.writerows(ROWS)
    print(f"\nWrote {len(ROWS)} rows to {outfile}")
else:
    print("No rows written; check API connectivity or parameters.")