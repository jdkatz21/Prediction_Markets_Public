

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Optional
import pandas as pd
from datetime import datetime

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Constants
DATA_DIR = '../../data/daily_distribution_data/'
FILES = {
    'fed_levels': 'daily_distributions_fed_levels.csv',
    'headline_cpi_releases': 'daily_distributions_headline_cpi_releases.csv',
    # 'unemployment_releases': 'daily_distributions_unemployment_releases.csv',
}
HORIZON_MAP = {
    'FED-25JUL': '2025-07-30',
    'FED-25SEP': '2025-09-17',
    'FED-25OCT': '2025-10-29',
    'FED-25DEC': '2025-12-10',
}


def load_and_process_csv(file_path: str, data_type: str) -> pd.DataFrame:
    df = pd.read_csv(file_path, parse_dates=['date', 'expiry_date'])
    df['type'] = data_type
    return df.rename(columns={'date': 'prediction_date', 'expiry_date': 'horizon_date'})


def apply_horizon_override(df: pd.DataFrame) -> pd.DataFrame:
    df['horizon_date'] = df.apply(
        lambda row: pd.to_datetime(HORIZON_MAP[row['contract_preamble']])
        if row['contract_preamble'] in HORIZON_MAP else row['horizon_date'],
        axis=1
    )
    return df


# Load and prepare all data
kalshi_data = pd.concat([
    apply_horizon_override(load_and_process_csv(f"{DATA_DIR}{FILES['fed_levels']}", 'fed_levels')),
    load_and_process_csv(f"{DATA_DIR}{FILES['headline_cpi_releases']}", 'headline_cpi_releases'),
    # load_and_process_csv(f"{DATA_DIR}{FILES['unemployment_releases']}", 'unemployment_releases'),
], ignore_index=True)


@app.get("/contracts")
def get_contracts(type: Optional[str] = None):
    df = kalshi_data
    if type:
        df = df[df["type"] == type]
    contracts_sorted = (
        df[["contract_preamble", "horizon_date"]]
        .dropna()
        .drop_duplicates()
        .sort_values("horizon_date", ascending=False)
        .contract_preamble
        .tolist()
    )
    return {"contracts": contracts_sorted}


@app.get("/distribution")
def get_distribution(
    contract_preamble: str,
    prediction_dates: List[str] = Query(..., max_length=2),
    smallest_bin: Optional[float] = None,
    largest_bin: Optional[float] = None
):
    df = kalshi_data[kalshi_data['contract_preamble'] == contract_preamble]
    output = {}

    for date_str in prediction_dates:
        d = pd.to_datetime(date_str)
        subset = df[df['prediction_date'] == d][['strike', 'probability']].copy()

        if subset.empty:
            output[date_str] = []
            continue

        # Handle lower bound
        if smallest_bin is not None:
            lower = subset[subset['strike'] < smallest_bin]
            lump = lower['probability'].sum()
            subset = subset[subset['strike'] >= smallest_bin]
            if lump > 0:
                subset = pd.concat([
                    pd.DataFrame([{'strike': smallest_bin, 'probability': lump}]),
                    subset
                ]) if smallest_bin not in subset['strike'].values else subset.assign(
                    probability=lambda x: x.apply(
                        lambda row: row['probability'] + lump if row['strike'] == smallest_bin else row['probability'],
                        axis=1
                    )
                )

        # Handle upper bound
        if largest_bin is not None:
            upper = subset[subset['strike'] > largest_bin]
            lump = upper['probability'].sum()
            subset = subset[subset['strike'] <= largest_bin]
            if lump > 0:
                subset = pd.concat([
                    subset,
                    pd.DataFrame([{'strike': largest_bin, 'probability': lump}])
                ]) if largest_bin not in subset['strike'].values else subset.assign(
                    probability=lambda x: x.apply(
                        lambda row: row['probability'] + lump if row['strike'] == largest_bin else row['probability'],
                        axis=1
                    )
                )

        output[date_str] = subset.sort_values('strike').to_dict(orient='records')

    strike_labels = sorted(kalshi_data[kalshi_data['contract_preamble'] == contract_preamble]['strike'].unique())

    return {
        "strike_labels": strike_labels,
        "data": output
    }


@app.get("/contract-info")
def get_contract_info(contract_preamble: str):
    df = kalshi_data[kalshi_data['contract_preamble'] == contract_preamble]
    if df.empty:
        return {}

    this_type = df['type'].iloc[0]
    this_horizon = df['horizon_date'].iloc[0]
    latest_pred = df['prediction_date'].max()

    today = pd.to_datetime("today").normalize()

    # Only horizons from same contract type
    type_horizons = kalshi_data[kalshi_data['type'] == this_type][['contract_preamble', 'horizon_date']]
    type_horizons = type_horizons.drop_duplicates().sort_values('horizon_date')

    previous_horizons = type_horizons[type_horizons['horizon_date'] < this_horizon]
    past_horizons = previous_horizons[previous_horizons['horizon_date'] < today]

    previous_valid = past_horizons['horizon_date'].max() if not past_horizons.empty else None

    return {
        "horizon_date": this_horizon.date(),
        "previous_horizon_date": previous_valid.date() if previous_valid is not None else None,
        "latest_prediction_date": latest_pred.date()
    }

@app.get("/types")
def get_types():
    return {"types": kalshi_data["type"].dropna().unique().tolist()}

@app.get("/prediction-dates")
def get_prediction_dates(contract_preamble: str, type: str):
    filtered = kalshi_data[
        (kalshi_data["contract_preamble"] == contract_preamble) &
        (kalshi_data["type"] == type)
    ]
    if filtered.empty:
        return {"dates": []}

    unique_dates = filtered["prediction_date"].dropna().dt.strftime('%Y-%m-%d').unique()
    return {"dates": sorted(unique_dates)}
