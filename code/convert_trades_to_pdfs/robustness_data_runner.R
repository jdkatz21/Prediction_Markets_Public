# This file is a driver to convert all of our trade level and orderbook data to 
# moments and probability distribution data


############ Trade-level Data ############
source("code/convert_trades_to_pdfs/convert_trade_level_data_cdfs.R")


# FFR levels-- VWAP
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_fed_levels.csv',
                      output_distributions = 'data/robustness_data/fed_distributions/daily_distributions_fed_levels_vwap.csv',
                      output_moments = 'data/robustness_data/fed_moments/daily_moments_fed_levels_vwap.csv',
                      strike_int = 0.25,
                      days_before_horizon = 180,
                      moment_adjustment = .125,
                      convert_to_daily_method = 'VWAP',
                      clean_data_method = 'middle-out')

# FFR levels-- left-to-right
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_fed_levels.csv',
                      output_distributions = 'data/robustness_data/fed_distributions/daily_distributions_fed_levels_left_to_right.csv',
                      output_moments = 'data/robustness_data/fed_moments/daily_moments_fed_levels_left_to_right.csv',
                      strike_int = 0.25,
                      days_before_horizon = 180,
                      moment_adjustment = .125,
                      convert_to_daily_method = 'last',
                      clean_data_method = 'left-to-right')

# FFR levels-- right-to-left
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_fed_levels.csv',
                      output_distributions = 'data/robustness_data/fed_distributions/daily_distributions_fed_levels_right_to_left.csv',
                      output_moments = 'data/robustness_data/fed_moments/daily_moments_fed_levels_right_to_left.csv',
                      strike_int = 0.25,
                      days_before_horizon = 180,
                      moment_adjustment = .125,
                      convert_to_daily_method = 'last',
                      clean_data_method = 'right-to-left')


# CPI levels-- VWAP
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_headline_cpi_releases.csv',
                      output_distributions = 'data/robustness_data/cpi_distributions/daily_distributions_cpi_vwap.csv',
                      output_moments = 'data/robustness_data/cpi_moments/daily_moments_cpi_vwap.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1,
                      convert_to_daily_method = 'VWAP',
                      clean_data_method = 'middle-out')

# CPI levels-- left-to-right
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_headline_cpi_releases.csv',
                      output_distributions = 'data/robustness_data/cpi_distributions/daily_distributions_cpi_left_to_right.csv',
                      output_moments = 'data/robustness_data/cpi_moments/daily_moments_cpi_left_to_right.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1,
                      convert_to_daily_method = 'last',
                      clean_data_method = 'left-to-right')

# CPI levels-- right-to-left
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_headline_cpi_releases.csv',
                      output_distributions = 'data/robustness_data/cpi_distributions/daily_distributions_cpi_right_to_left.csv',
                      output_moments = 'data/robustness_data/cpi_moments/daily_moments_cpi_right_to_left.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1,
                      convert_to_daily_method = 'last',
                      clean_data_method = 'right-to-left')

# Unemployment-- VWAP
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_unemployment.csv',
                      output_distributions = 'data/robustness_data/unemployment_distributions/daily_distributions_unemployment_vwap.csv',
                      output_moments = 'data/robustness_data/unemployment_moments/daily_moments_unemployment_vwap.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1,
                      convert_to_daily_method = 'VWAP',
                      clean_data_method = 'middle-out')

# Unemployment-- left-to-right
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_unemployment.csv',
                      output_distributions = 'data/robustness_data/unemployment_distributions/daily_distributions_unemployment_left_to_right.csv',
                      output_moments = 'data/robustness_data/unemployment_moments/daily_moments_unemployment_left_to_right.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1,
                      convert_to_daily_method = 'last',
                      clean_data_method = 'left-to-right')

# Unemployment-- right-to-left
extract_distributions(input_file = 'data/trade_level_data/trade_level_data_unemployment.csv',
                      output_distributions = 'data/robustness_data/unemployment_distributions/daily_distributions_unemployment_right_to_left.csv',
                      output_moments = 'data/robustness_data/unemployment_moments/daily_moments_unemployment_right_to_left.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30,
                      moment_adjustment = .1,
                      convert_to_daily_method = 'last',
                      clean_data_method = 'right-to-left')


############ Order-book Data ############
# source("code/convert_trades_to_pdfs/convert_bid_ask_data_cdfs.R")

# FFR levels
# extract_distributions(input_file = 'data/orderbook_data/daily_bid_ask_fed_decisions_data.csv',
#                       output_distributions = 'data/daily_bid_ask_distribution_data/daily_distributions_fed_levels.csv',
#                       output_moments = 'data/daily_bid_ask_moments_data/daily_moments_fed_levels.csv',
#                       strike_int = 0.25,
#                       days_before_horizon = 180,
#                       moment_adjustment = .125)
# 
# # CPI YoY Headline
# extract_distributions(input_file = 'data/orderbook_data/daily_bid_ask_cpi_data.csv',
#                       output_distributions = 'data/daily_bid_ask_distribution_data/daily_distributions_headline_cpi_releases.csv',
#                       output_moments = 'data/daily_bid_ask_moments_data/daily_moments_headline_cpi_releases.csv',
#                       strike_int = 0.1,
#                       days_before_horizon = 30,
#                       moment_adjustment = .1)
# 
# # Unemployment
# extract_distributions(input_file = 'data/orderbook_data/daily_bid_ask_unemployment_data.csv',
#                       output_distributions = 'data/daily_bid_ask_distribution_data/daily_distributions_unemployment_releases.csv',
#                       output_moments = 'data/daily_bid_ask_moments_data/daily_moments_unemployment_releases.csv',
#                       strike_int = 0.1,
#                       days_before_horizon = 30,
#                       moment_adjustment = .1)



