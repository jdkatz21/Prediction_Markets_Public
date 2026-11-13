# Replication Package for Kalshi and the Rise of Macro Markets (2026)

## Overview

This replication package constructs the data from Kalshi used in *Diercks, Katz, Wright (2026)* using Python and R. It also creates a small website and GitHub Action that highlights the data and continually updates it over time.

Constructing the full dataset from scratch through present-day takes approximately 1.5 hours (as of November 2026).

---

## Data Availability

Kalshi data for some macroeconomic series can be explored and visualized directly on [econfutures.com](https://econfutures.com), which is updated regularly.

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
  with:
    use-public-rspm: true

- name: Install R dependencies
  run: |
    install.packages(c("tidyverse", "lubridate", "matrixStats", "collapse", "DescTools"))
  shell: Rscript {0}

- name: Run R script to convert to PDFs and Moments Data
  run: Rscript code/convert_trades_to_pdfs/data_convert_runner.R
```

---

## Citation

If you use this code, please cite:

> Diercks, Katz, Wright (2026). *Kalshi and the Rise of Macro Markets.* NBER Working Paper.
> https://www.nber.org/papers/w34702
