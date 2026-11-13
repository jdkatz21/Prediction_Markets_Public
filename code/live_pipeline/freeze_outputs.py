"""
freeze_outputs.py

Author: Anthony M. Diercks, Jared Dean Katz
Affiliation: Federal Reserve Board of Governors, Northwestern University Kellogg School of Businesss
Contact: jared.katz@kellogg.northwestern.edu
Date: November 2026

Description:
-------------
Makes sure that data posted on econfutures.com never changes once it is posted.

data_convert_runner.R recomputes every distribution and moment from scratch each
day. For a day that is complete, the probabilities and moments come out the same
every time, but two things can still differ between runs for markets that are
still trading: the expiry_date column (the last day with a trade so far) moves
forward, and days that fall out of the days_before_horizon window are dropped.

This script runs after the R step. For each output file, it keeps every row
that was already published exactly as it was posted (as text, so not even the
number formatting changes), and adds only the rows for days after the last
published day. It then records the last published day in frozen_through.txt.

If there is no frozen_through.txt among the published files (the first run),
the R output is published as-is.

Usage:
------
Run from the repo root, after data_convert_runner.R:

    python code/live_pipeline/freeze_outputs.py published

where `published` is a folder holding the currently published files, in the
same layout as data/ (daily_distribution_data, daily_moments_data and
frozen_through.txt).

License & Citation:
--------------------
This script is distributed under the MIT License (see LICENSE file).
If you use this script or data collected with it in published work,
please cite:

Diercks, Katz, Wright (2026)

with use.
"""

import os
import sys
import glob
import pandas as pd

DATA_DIR = 'data'
OUTPUT_DIRS = ['daily_distribution_data', 'daily_distribution_data/wide', 'daily_moments_data']
MARKER = 'frozen_through.txt'

# The last complete day (UTC): update_trades.py only keeps trades before today
LAST_COMPLETE_DAY = (pd.Timestamp.now(tz='UTC').normalize() - pd.Timedelta(days=1)).strftime('%Y-%m-%d')


def read_as_text(path: str) -> pd.DataFrame:
    """Read a csv keeping every value exactly as written (no number or NA parsing)."""
    return pd.read_csv(path, dtype=str, keep_default_na=False)


def freeze_file(new_path: str, published_path: str, frozen_through: str) -> None:
    new = read_as_text(new_path)

    if not os.path.exists(published_path):
        print(f"  {new_path}: not published yet, publishing as-is")
        return

    published = read_as_text(published_path)
    added = new[new['date'] > frozen_through]

    combined = pd.concat([published, added], ignore_index=True)

    # A new strike adds a column to the wide files; earlier rows have no value for it
    combined = combined.fillna('NA')

    combined.to_csv(new_path, index=False)
    print(f"  {new_path}: kept {len(published)} published rows, added {len(added)}")


if __name__ == '__main__':
    published_dir = sys.argv[1]
    marker_path = os.path.join(published_dir, MARKER)

    if os.path.exists(marker_path):
        with open(marker_path) as f:
            frozen_through = f.read().strip()
        print(f"Published data is frozen through {frozen_through}")

        for output_dir in OUTPUT_DIRS:
            for new_path in sorted(glob.glob(os.path.join(DATA_DIR, output_dir, '*.csv'))):
                published_path = os.path.join(published_dir, os.path.relpath(new_path, DATA_DIR))
                freeze_file(new_path, published_path, frozen_through)
    else:
        print(f"No {MARKER} in {published_dir}: first run, publishing the R output as-is")

    with open(os.path.join(DATA_DIR, MARKER), 'w') as f:
        f.write(LAST_COMPLETE_DAY + '\n')
    print(f"Data now frozen through {LAST_COMPLETE_DAY}")
