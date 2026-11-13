# This file is the website's version of code/convert_trades_to_pdfs/data_convert_runner.R.
# It runs the paper's code with the same settings, with one difference for contracts
# that are still trading.
#
# The paper's code sets each contract's expiry_date to its last day with a trade, and
# keeps the days_before_horizon days before it. In the paper every contract has already
# expired, so that is the day of the meeting or release. A contract that is still
# trading has no last day yet; its last trade so far would place the window in the
# wrong place. Here, those contracts use Kalshi's scheduled close date instead, saved to
# data/close_dates by code/live_pipeline/update_trades.py. Contracts that have expired
# are treated exactly as in the paper.
#
# The paper's code itself is not changed: this file loads it and replaces only
# fill_dataless_days, where expiry_date is set.

############ Trade-level Data ############
source("code/convert_trades_to_pdfs/convert_trade_level_data_cdfs.R")

read_close_dates <- function(name) {
  path <- file.path("data/close_dates", paste0("close_dates_", name, ".csv"))
  if (!file.exists(path)) {
    stop(paste("Missing", path, "- run code/live_pipeline/update_trades.py first"))
  }
  read_csv(path, col_types = cols(contract_preamble = col_character(), close_date = col_date()))
}

# Scheduled close dates for the series being converted (set before each call below)
website_close_dates <- NULL

# The paper's fill_dataless_days (code/convert_trades_to_pdfs/convert_trade_level_data_cdfs.R),
# unchanged except for the marked step that uses scheduled close dates
fill_dataless_days <- function(df, days_before_horizon) {


  # Get unique strike-preamble combinations that actually exist
  valid_combos <- df %>% select(contract_preamble, strike) %>% distinct()

  # Get full date range
  dates <- seq(min(df$date), max(df$date), by = "day")

  # Create full date range for only valid strike-preamble combos
  full_date_range <- valid_combos %>%
    crossing(date = dates)

  # Merge with current df
  df <- df %>% full_join(full_date_range) %>%
    arrange(contract_preamble, strike, date)

  # get the contract expiry date
  df <- df %>%
    group_by(contract_preamble) %>%
    mutate(
      expiry_date = if (all(is.na(yes_price))) NA_Date_ else max(date[!is.na(yes_price)])
    ) %>%
    ungroup()

  # WEBSITE ONLY: a contract that is still trading uses its scheduled close as expiry_date
  if (!is.null(website_close_dates)) {
    df <- df %>%
      left_join(website_close_dates %>% transmute(contract_preamble, scheduled_close = close_date),
                by = "contract_preamble") %>%
      mutate(expiry_date = coalesce(scheduled_close, expiry_date)) %>%
      select(-scheduled_close)
  }

  # Get rid of stale prices that might get stuck because they took place before
  # the forecast period we care about (Ex: July 2023 CPI)
  df <- df %>% filter(date  >= expiry_date - days(days_before_horizon) - 10)

  # fill NA rows with last price and fill in 0 for daily volume on these days
  df <- df %>%
    group_by(contract_preamble, strike) %>%
    fill(yes_price, .direction = "down") %>%
    ungroup() %>% mutate(
      daily_volume = ifelse(is.na(daily_volume), 0, daily_volume)
    )

  # remove the rows at the start with no price, rows after the expiry date, and
  # rows for bins that never existed
  df <- df %>% na.omit() %>%
    filter(
      date <= expiry_date
    )


  return(df)
}

# FFR levels
website_close_dates <- read_close_dates('fed_levels')
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_fed_levels.csv',
                      output_distributions = 'data/daily_distribution_data/daily_distributions_fed_levels.csv',
                      output_moments = 'data/daily_moments_data/daily_moments_fed_levels.csv',
                      output_wide = 'data/daily_distribution_data/wide/daily_distributions_fed_levels.csv',
                      strike_int = 0.25,
                      days_before_horizon = 180,
                      moment_adjustment = .125)

# CPI YoY headline
website_close_dates <- read_close_dates('headline_cpi_releases')
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_headline_cpi_releases.csv',
                      output_distributions = 'data/daily_distribution_data/daily_distributions_headline_cpi_releases.csv',
                      output_moments = 'data/daily_moments_data/daily_moments_headline_cpi_releases.csv',
                      output_wide = 'data/daily_distribution_data/wide/daily_distributions_headline_cpi_releases.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1)

# CPI YoY core
website_close_dates <- read_close_dates('core_cpi_releases')
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_core_cpi_releases.csv',
                      output_distributions = 'data/daily_distribution_data/daily_distributions_core_cpi_releases.csv',
                      output_moments = 'data/daily_moments_data/daily_moments_core_cpi_releases.csv',
                      output_wide = 'data/daily_distribution_data/wide/daily_distributions_core_cpi_releases.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1)

# CPI MoM headline
website_close_dates <- read_close_dates('headline_cpi_releases_mom')
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_headline_cpi_releases_mom.csv',
                      output_distributions = 'data/daily_distribution_data/daily_distributions_headline_cpi_releases_mom.csv',
                      output_moments = 'data/daily_moments_data/daily_moments_headline_cpi_releases_mom.csv',
                      output_wide = 'data/daily_distribution_data/wide/daily_distributions_headline_cpi_releases_mom.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1)

# Unemployment
website_close_dates <- read_close_dates('unemployment')
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_unemployment.csv',
                      output_distributions = 'data/daily_distribution_data/daily_distributions_unemployment_releases.csv',
                      output_moments = 'data/daily_moments_data/daily_moments_unemployment_releases.csv',
                      output_wide = 'data/daily_distribution_data/wide/daily_distributions_unemployment_releases.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1)


############ Trade-level Data-- Annual ############
# The annual series use no window before the horizon. Loading the paper's annual code
# also restores its own fill_dataless_days for these two series.
source("code/convert_trades_to_pdfs/convert_trade_level_data_pdfs.R")

# CPI end of year
extract_distributions(
  input_file = "data/trade_level_data/trade_level_data_headline_cpi_end_of_year.csv",
  output_distributions = "data/daily_distribution_data/daily_distributions_headline_cpi_end_of_year.csv",
  output_moments = "data/daily_moments_data/daily_moments_headline_cpi_end_of_year.csv",
  output_wide = "data/daily_distribution_data/wide/daily_distributions_headline_cpi_end_of_year.csv"
)

# GDP end of year
extract_distributions(
  input_file = "data/trade_level_data/trade_level_data_gdp_end_of_year.csv",
  output_distributions = "data/daily_distribution_data/daily_distributions_gdp_end_of_year.csv",
  output_moments = "data/daily_moments_data/daily_moments_gdp_end_of_year.csv",
  output_wide = "data/daily_distribution_data/wide/daily_distributions_gdp_end_of_year.csv"
)
