"""
update_trades.py

Author: Anthony M. Diercks, Jared Dean Katz
Affiliation: Federal Reserve Board of Governors, Northwestern University Kellogg School of Businesss
Contact: jared.katz@kellogg.northwestern.edu
Date: November 2026

Description:
-------------
Incrementally updates the trade-level data behind econfutures.com. Unlike
code/kalshi_scraping/scrape_kalshi_trades.py, which downloads every trade from
scratch (and is kept as-is for replicating the paper), this script starts from
the existing trade files in data/trade_level_data and only adds what is new:

    - Markets that Kalshi has moved to its historical endpoint are finished and
      are never downloaded again.
    - Markets still on the live endpoint (open, or recently closed) are the only
      ones that can have new trades. For each one already in the archive, only
      trades after its latest saved trade are requested (from both endpoints,
      since Kalshi moves a market's older trades to the historical endpoint).
    - Markets that are new to the archive get their full history.

If a series has no trade file yet, its full history is downloaded, the same way
scrape_kalshi_trades.py does it.

Only complete days are kept: trades from the current day (in UTC, which is the
day the R code assigns each trade to) are left out and picked up by the next
day's run. Once a day is in the archive, no more trades are added to it.

The trade files have the same names and columns as scrape_kalshi_trades.py. The
script also saves each live contract's scheduled close date to data/close_dates,
which code/live_pipeline/convert_runner.R uses to place the window before each
meeting or release for contracts that are still trading.

Usage:
------
Run from the repo root:

    python code/live_pipeline/update_trades.py                  # all series
    python code/live_pipeline/update_trades.py fed_levels       # some series

Credentials are read the same way as scrape_kalshi_trades.py: KALSHI_KEYID and
KALSHI_PRIVATE_KEY (the key itself or a path to the key file), from the
environment or from env.env.

License & Citation:
--------------------
This script is distributed under the MIT License (see LICENSE file).
If you use this script or data collected with it in published work,
please cite:

Diercks, Katz, Wright (2026)

with use.
"""

##################################
##     Package Installation     ##
##################################

import os
import sys
import time
import pandas as pd
from dotenv import load_dotenv
from cryptography.hazmat.primitives import serialization

repo_root = os.getcwd()
sys.path.append(os.path.join(repo_root, "code/kalshi_scraping"))

from clients_kalshi import KalshiHttpClient, Environment
import tickers


##################################
##        Configuration         ##
##################################

# Series kept up to date on the website: name -> Kalshi series ticker.
# Names match the trade files read by data_convert_runner.R.
SERIES = {
    'fed_levels':                 'KXFED',
    'headline_cpi_releases':      'KXCPIYOY',
    'headline_cpi_end_of_year':   'KXACPI',
    'core_cpi_releases':          'KXCPICOREYOY',
    'headline_cpi_releases_mom':  'KXCPI',
    'gdp_end_of_year':            'KXGDPYEAR',
    'unemployment':               'KXU3',
}

TRADE_DIR = 'data/trade_level_data'
CLOSE_DATE_DIR = 'data/close_dates'

HISTORICAL_TRADES_URL = "/trade-api/v2/historical/trades"
LIVE_TRADES_URL = "/trade-api/v2/markets/trades"
LIVE_MARKETS_URL = "/trade-api/v2/markets"

# Re-request a little before the latest saved trade, in case several trades
# share its timestamp; duplicates are dropped by trade_id
OVERLAP_SECONDS = 60

# Keep only trades before the start of today (UTC), so every saved day is complete
CUTOFF = pd.Timestamp.now(tz='UTC').normalize()


##################################
## Connecting to the Kalshi API ##
##################################

def make_client() -> KalshiHttpClient:
    if os.path.exists("env.env"):
        load_dotenv("env.env")

    key_id = os.getenv("KALSHI_KEYID")
    private_key_str = os.getenv("KALSHI_PRIVATE_KEY")

    # KALSHI_PRIVATE_KEY can be either the key itself (GitHub Actions secret) or
    # a path to the key file (local, e.g. KALSHI_PRIVATE_KEY=key.txt in env.env)
    if private_key_str.lstrip().startswith("-----BEGIN"):
        private_key_bytes = private_key_str.encode()
    else:
        with open(private_key_str, "rb") as f:
            private_key_bytes = f.read()

    private_key = serialization.load_pem_private_key(private_key_bytes, password=None)

    return KalshiHttpClient(key_id=key_id, private_key=private_key, environment=Environment.PROD)


##################################
##     Downloading the data     ##
##################################

def paginate(client, url: str, params: dict, result_key: str) -> list:
    """Collect every page of a Kalshi list endpoint, keeping filters on each page."""
    results = []
    cursor = None

    while True:
        page_params = dict(params)
        if cursor:
            page_params['cursor'] = cursor

        page = client.get(url, params=page_params)
        results.extend(page.get(result_key, []))

        cursor = page.get('cursor')
        if not cursor:
            return results


def live_markets(client, series_ticker: str) -> list:
    """Markets in a series that are still on the live endpoint, i.e. can get new trades."""
    return paginate(client, LIVE_MARKETS_URL,
                    {'series_ticker': series_ticker, 'limit': 1000}, 'markets')


def save_close_dates(name: str, markets: list) -> None:
    """
    Save each live contract's scheduled close date (UTC) for the R step. For finished
    contracts the R code uses the last day with a trade as the expiry date; contracts
    still trading have no last day yet, so their window before the meeting or release
    is anchored on the scheduled close instead (see code/live_pipeline/convert_runner.R).
    """
    closes = {}
    for m in markets:
        event, close = m['event_ticker'], m['close_time'][:10]
        closes[event] = max(closes.get(event, close), close)

    os.makedirs(CLOSE_DATE_DIR, exist_ok=True)
    path = os.path.join(CLOSE_DATE_DIR, f'close_dates_{name}.csv')
    pd.DataFrame(sorted(closes.items()), columns=['contract_preamble', 'close_date']).to_csv(path, index=False)
    print(f"  Saved scheduled close dates for {len(closes)} contracts to {path}")


def trade_times(trades: pd.DataFrame) -> pd.Series:
    """Trade times in UTC, to the second (Kalshi varies the number of fractional digits)."""
    return pd.to_datetime(trades['created_time'].str.slice(0, 19), utc=True, format='%Y-%m-%dT%H:%M:%S')


def before_cutoff(trades: pd.DataFrame) -> pd.DataFrame:
    """Drop trades from the current (incomplete) UTC day."""
    if trades.empty:
        return trades
    return trades[trade_times(trades) < CUTOFF]


def fetch_new_trades(client, ticker: str, after) -> pd.DataFrame:
    """
    Trades for one market before CUTOFF, from both endpoints (Kalshi moves a market's
    older trades to the historical endpoint while newer ones stay live). If `after`
    (a UTC timestamp) is given, only trades since then; otherwise the full history.
    """
    params = {'ticker': ticker, 'limit': 1000, 'max_ts': int(CUTOFF.timestamp()) - 1}

    if after is not None:
        params['min_ts'] = int(after.timestamp()) - OVERLAP_SECONDS

    historical = paginate(client, HISTORICAL_TRADES_URL, params, 'trades')
    live = paginate(client, LIVE_TRADES_URL, params, 'trades')
    return before_cutoff(pd.DataFrame(historical + live))


def full_scrape(client, series_ticker: str) -> pd.DataFrame:
    """Full trade history for every market in a series (used when there is no archive yet)."""
    all_trades = []
    for ticker in tickers.autogenerate_kalshi_tickers(series_ticker):
        print(f"  {ticker}: full history")
        all_trades.append(before_cutoff(client.get_all_trades_for_ticker(ticker)))
        time.sleep(1)
    return pd.concat(all_trades, ignore_index=True)


def update_series(client, name: str, series_ticker: str) -> None:
    path = os.path.join(TRADE_DIR, f'trade_level_data_{name}.csv')
    print(f"\n=== {name} ({series_ticker}) ===")

    markets = live_markets(client, series_ticker)
    save_close_dates(name, markets)

    if not os.path.exists(path):
        print(f"  No archive at {path}, downloading full history")
        before = 0
        combined = full_scrape(client, series_ticker)

    else:
        # An archive made by a full scrape can include part of today; drop it so
        # today is only ever added once it is complete
        archive = before_cutoff(pd.read_csv(path))
        before = len(archive)
        latest = trade_times(archive).groupby(archive['ticker']).max()

        new_trades = []
        for ticker in [m['ticker'] for m in markets]:
            after = latest.get(ticker)
            trades = fetch_new_trades(client, ticker, after)
            label = "full history" if after is None else f"since {after}"
            print(f"  {ticker} ({label}): {len(trades)} trades")
            new_trades.append(trades)

        combined = pd.concat([archive] + new_trades, ignore_index=True)

    if combined.empty:
        print("  No trades found, nothing saved")
        return

    combined = combined.drop_duplicates(subset='trade_id')
    combined = combined.sort_values('created_time').reset_index(drop=True)

    os.makedirs(TRADE_DIR, exist_ok=True)
    combined.to_csv(path, index=False)
    print(f"  Saved {len(combined)} trades to {path} ({len(combined) - before} new)")


##################################
##       Getting the data       ##
##################################

if __name__ == '__main__':
    selected = sys.argv[1:] or list(SERIES)

    unknown = [name for name in selected if name not in SERIES]
    if unknown:
        sys.exit(f"Unknown series: {', '.join(unknown)}. Choose from: {', '.join(SERIES)}")

    print(f"Keeping trades before {CUTOFF} (start of today, UTC)")
    client = make_client()
    for name in selected:
        update_series(client, name, SERIES[name])
