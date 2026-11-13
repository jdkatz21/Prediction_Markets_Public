# Replication Package for Kalshi and the Rise of Macro Markets (2026)

Note: In March 2026 Kalshi split its API into historical and live endpoints, with trades moving to the historical endpoint after a cutoff (about 100 days at the time of writing). The scraper pulls each market's trades from both endpoints and combines them, so the full trade history is downloaded.

## Overview

This replication package constructs the data from Kalshi used in *Diercks, Katz, Wright (2026)* using Python and R. It also creates a small website and GitHub Action that highlights the data and continually updates it over time.

To construct the dataset from scratch (downloading raw trade data from Kalshi and converting it into forecasts), the process takes approximately **1.5 hours**.

The website updates via a GitHub Action every Friday afternoon, pulling the most recent data, rerunning the methodology to generate forecasts, and updating the website with the latest results.

---

## Data Availability

All Kalshi data is pulled from their public API. Replicators will need to establish their own API credentials (stored as environment variables) to connect, but there is no private data involved. Permission from Kalshi to use the data for research purposes has been granted. Kalshi's data licensing agreement is included in this repository as `/API Developer Agreement.pdf`.

This package contains only the Kalshi data used in the paper. Fed Funds Futures and Bloomberg data were used as property of/licensed by the Federal Reserve Board and are not included. Survey of Primary Dealers data can be accessed publicly via the NY Fed. The replication archive is limited to work and figures involving Kalshi data only.

The data is not stored in this repository. All of the Kalshi data below, raw and derived, can be downloaded from [econfutures.com](https://econfutures.com), where it is kept up to date as new trades arrive. Everything can also be regenerated with the code in this repository.

| Data file | Source | Notes | Provided |
|-----------|--------|-------|----------|
| `data/trade_level_data` | Kalshi | Raw trade-level data | Yes, at econfutures.com (w/ code to generate updates) |
| `data/orderbook_data` | Kalshi | Raw orderbook data | Yes, at econfutures.com (w/ code to generate updates) |
| `data/daily_distribution_data` | Kalshi | Derived daily-frequency distributions | Yes, at econfutures.com (w/ code to generate from `trade_level_data`) |
| `data/daily_moments_data` | Kalshi | Derived daily-frequency moments | Yes, at econfutures.com (w/ code to generate from `trade_level_data`) |
| `data/daily_bid_ask_distribution_data` | Kalshi | Derived daily-frequency bid/ask distributions | Yes, at econfutures.com (w/ code to generate from `orderbook_data`) |
| `data/daily_bid_ask_moments_data` | Kalshi | Derived daily-frequency bid/ask moments | Yes, at econfutures.com (w/ code to generate from `orderbook_data`) |
| Bloomberg Economic Releases | Bloomberg | — | No |
| Bloomberg Consensus Forecasts | Bloomberg | — | No |
| Survey of Primary Dealers Forecasts | NY Fed | — | No |
| Federal Funds Rate Futures | CME | — | No |
| SOFR Rates | CME | — | No |

---

## Usage

The primary purposes of this package are:

1. **Transparency** about methodological decisions when extracting Kalshi-implied forecasts from raw data.
2. **A starting point for researchers** using prediction market data.

Following this package should provide a quick introduction to extracting Kalshi orderbook and trade-level data, converting raw data into market-implied probability distributions, and constructing moments from those distributions for analysis.

In *Diercks, Katz, Wright (2026)*, these moments and distributions are used for analysis — the auxiliary data and code for that analysis are **not** included in this public repository. The repository does include the code that generates the interactive data exploration website at [econfutures.com](https://econfutures.com) (`docs/index.html`), which updates continuously as new data arrives.

---

## Instructions for Replicators

1. Clone or download this repository and navigate to the root directory.

2. Create `env.env` file in the root directory with your Kalshi API credentials:
```
   KALSHI_KEYID=your_key_here
   KALSHI_PRIVATE_KEY=key.txt
```
   `KALSHI_PRIVATE_KEY` can be either the path to your private key file (as above) or the key itself, which is how it is stored as a GitHub Actions secret.
   To obtain credentials, register at [Kalshi's developer portal](https://docs.kalshi.com/welcome).

3. Install the Python (3.11) and R dependencies listed below.

4. **To download fresh data:** Run `python code/kalshi_scraping/scrape_kalshi_trades.py` from the
   repo root. This populates `data/trade_level_data` for every series used on the website. To download
   only some series, name them, e.g. `python code/kalshi_scraping/scrape_kalshi_trades.py headline_cpi_releases fed_levels`
   (the full list is in `SERIES` at the bottom of the script). Add `--info` to also save how and when each
   market resolved to `data/ticker_info`. Orderbook data in `data/orderbook_data` comes from
   `code/kalshi_scraping/orderbook_scraping.py`.
   **To use provided data:** Download it from [econfutures.com](https://econfutures.com) into the matching
   `data/` folders and skip this step (or steps 4 and 5 if you download the distributions and moments too).
   
5. Run `Rscript code/convert_trades_to_pdfs/data_convert_runner.R` from the repo root to generate daily-frequency moments and distributions.

### Python Dependencies

```
pandas, python-dotenv, cryptography, requests, websockets
```

Python version: **3.11**

### R Dependencies

```r
install.packages(c("tidyverse", "lubridate", "matrixStats", "collapse", "DescTools"))
```

### Full YAML workflow to get most recent data (See `.github/workflows` to see how website updates)

```yaml
# Python setup
- name: Set up Python
  uses: actions/setup-python@v5
  with:
    python-version: "3.11"

- name: Install Python dependencies
  run: |
    pip install pandas python-dotenv cryptography requests websockets

- name: Run Python scraping script
  env:
    KALSHI_KEYID: ${{ secrets.KALSHI_KEYID }}
    KALSHI_PRIVATE_KEY: ${{ secrets.KALSHI_PRIVATE_KEY }}
  run: python code/kalshi_scraping/scrape_kalshi_trades.py

# R setup
- name: Set up R
  uses: r-lib/actions/setup-r@v2

- name: Install R dependencies
  run: |
    install.packages(c("tidyverse", "lubridate", "matrixStats", "collapse", "DescTools"),
                    repos = c("https://packagemanager.posit.co/cran/__linux__/jammy/latest",
                             "https://cloud.r-project.org"))
  shell: Rscript {0}

- name: Run R script to convert to PDFs and Moments Data
  run: Rscript code/convert_trades_to_pdfs/data_convert_runner.R
```

---

## Citation

If you use this package, please cite:

> Diercks, Katz, Wright (2026). *Kalshi and the Rise of Macro Markets.* NBER Working Paper.
> https://www.nber.org/papers/w34702
