# 
# convert_trade_level_data_pdfs.R
# 
# Author: Anthony M. Diercks, Jared Dean Katz
# Affiliation: Federal Reserve Board of Governors, Northwestern University Kellogg School of Businesss
# Contact: jared.katz@kellogg.northwestern.edu
# Date: July 2025
# 
# Description:
# -------------
# This script uses the Kalshi API to download and archive all contracts where
# there are strikes that outline a pdf (as opposed to the typical cdf)
# It is designed for researchers to be able to obtain current
# prediction market data.
# 
# 
# Usage:
# ------
# 
# Dependencies:
# -------------
# - R version 4.3.0
# - Kalshi API
# 
# 
# License & Citation:
# --------------------
# This script is distributed under the MIT License (see LICENSE file).
# If you use this script or data collected with it in published work,
# please cite:
#     
# Diercks, Katz (2025) 
# 
# with use.
# 
# Disclaimer:
# -----------
# This is academic software provided 'as is', without warranty of any kind.
# Use at your own risk and verify data with official sources where appropriate.
# 
# Reproducibility:
# ----------------
# 
# Run on Macbook M1 in R Studio environment using R version 4.3.0

##################################
##     Package Installation     ##
##################################


library(tidyverse)
library(lubridate)
library(av)
library(matrixStats)
library(gganimate)

setwd('/Users/jaredkatz/Documents/Research/PredictionMarketsPublic')


#' Convert trade-level Kalshi data to daily summary
#'
#' Takes the last trade of each day as the daily value, and aggregates volume.
#'
#' @param df A data frame containing trade-level options data with columns: date, contract_preamble, strike, yes_price, count (volume)
#' @return A data frame with daily last prices and total volume per contract and strike.
read_data <- function(input_file) {
  
  df <- read_csv(input_file)
  
  # Convert datetime and extract date
  df <- df %>%
    mutate(created_time = as.POSIXct(created_time, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"),
           date = as.Date(created_time))
  
  # Extract contract_preamble and strike price
  df <- df %>%
    mutate(
      contract_preamble = str_extract(ticker, ".*(?=-[^-]*$)"),
      strike_raw = str_extract(ticker, "[^-]+$"),
      strike = as.numeric(str_remove(strike_raw, "^[A-Za-z]"))    
      ) %>% select(-strike_raw) %>%
    arrange(contract_preamble, strike, date)
  
  
  return(df)
}

#' Fill missing days in daily data with last known price (from a previous day)
#'
#' Ensures each valid contract_preamble and strike pair has data for every date in the full range.
#' Fills forward the last known price, sets daily volume to 0 on filled days,
#' and trims data outside the active contract period.
#'
#' @param df A data frame with columns: date, contract_preamble, strike, yes_price, daily_volume.
#' @return A data frame with missing dates filled and cleaned.
convert_to_daily <- function(df) {
  
  df <- df %>% group_by(date, contract_preamble, strike) %>%
    reframe(date=date, 
            contract_preamble = contract_preamble,
            strike = strike,
            yes_price = weighted.mean(yes_price, count),
            daily_volume = sum(count)) %>% distinct() %>%
    arrange(contract_preamble, strike, date)
  
}


#' Clean daily data by filtering and adjusting price bins
#'
#' Filters to 6 months before contract expiry, computes next higher strike bin,
#' and enforces non-decreasing adjusted prices across strikes (per contract and date).
#'
#' @param df A data frame with columns: date, expiry_date, contract_preamble, strike, yes_price, daily_volume.
#' @return A cleaned data frame with bin_high and adjusted_yes_price columns added.
fill_dataless_days <- function(df) {
  
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
  
  # fill NA rows with last price and fill in 0 for daily volume on these days
  df <- df %>%
    group_by(strike) %>%
    fill(yes_price, .direction = "down") %>%
    ungroup() %>% mutate(
      daily_volume = ifelse(is.na(daily_volume), 0, daily_volume)
    )
  
  
  # There are some really silly ticker names for CPI end-of-year distributions
  # which give us inaccurate strikes. Fix them here such that we have low, high, and midpoints of bins
  
  # first, get rid of the top and bottom bins for pdfs-- they're unreliable
  df <- df %>% filter(
                      (strike != 0.6 | contract_preamble != 'KXACPI-2025') & 
                      (strike != 6 | contract_preamble != 'KXACPI-2025') &
                        
                      (strike != 3 | contract_preamble != 'ACPI-22') &
                      (strike != 8.9 | contract_preamble != 'ACPI-22') &
                      
                      (strike != 1 | contract_preamble != 'ACPI-23') & 
                      (strike != 10 | contract_preamble != 'ACPI-23') &
                      
                      (strike != 1.5 | contract_preamble != 'ACPI-24') &
                      (strike != 1.5 | contract_preamble != 'ACPI-24')) 
  
  df <- df %>% mutate(

    # The 5.8 ticker is just listed under 5.75 for no good reason, so we fix.
    # The rest of the 2025 strikes are the midpoints of the bins, which is nice
    bin_low = ifelse(contract_preamble == 'KXACPI-2025' & strike == 5.75, 5.6,  strike - 0.2),
    bin_high = ifelse(contract_preamble == 'KXACPI-2025' & strike == 5.75, 6, strike + 0.2),
    midpoint = ifelse(contract_preamble == 'KXACPI-2025' & strike == 5.75, 5.8, strike)
    
  )
  
  
  # remove the rows at the start with no price, rows after the expiry date, and
  # rows for bins that never existed
  df <- df %>% na.omit() %>%
    filter(
      date <= expiry_date
    )

  return(df)
}



#' Convert adjusted prices to probability distributions
#'
#' Adds low-end bins to each contract/date slice, computes approximate probability
#' buckets by differencing adjusted prices, and iteratively swaps probabilities
#' to smooth out local inconsistencies.
#'
#' @param df A data frame with columns: contract_preamble, date, expiry_date, strike, adjusted_yes_price.
#' @return A data frame with an added `probability` column representing
#'         approximate probability mass for each strike bin.
convert_to_probabilities <- function(df) {
  
  # All we need to do is take the yes_price 's and make sure they add up to 100
  df <- df %>% group_by(contract_preamble, date) %>% arrange(strike) %>%
    mutate(sum = sum(yes_price),
           probability = yes_price * 100 / sum) %>% select(-sum)
  
  return(df)
}

weightedGMSkew <- function(x, w, na.rm = TRUE) {
  if (na.rm) {
    sel <- !is.na(x) & !is.na(w)
    x <- x[sel]; w <- w[sel]
  }
  w <- w / sum(w)
  mu <- sum(w * x)
  # weighted median
  ord <- order(x); x_o <- x[ord]; w_o <- w[ord]
  cumw <- cumsum(w_o)
  m_w <- x_o[min(which(cumw >= 0.5))]
  mad <- sum(w * abs(x - m_w))
  (mu - m_w) / mad
}

# return a new dataframe with the day and contract preamble and
# mean, median, mode, variance, skewness, kurtosis
get_moments <- function(df) {
  
  df <- df %>%
    group_by(date, contract_preamble, expiry_date) %>%
    summarise(
      mean     = sum(probability * midpoint, na.rm = TRUE) / sum(probability, na.rm = TRUE),
      median   = weightedMedian(midpoint, w = probability, na.rm = TRUE, interpolate = FALSE),
      mode = fmode(midpoint, w = probability, na.rm = TRUE, ties='first'),
      skewness = weightedGMSkew(midpoint, w = probability, na.rm = TRUE),
      kurtosis = DescTools::Kurt(midpoint, w = probability, na.rm = TRUE),
      variance = sum(probability * (midpoint - (sum(probability * midpoint) / sum(probability)))^2, na.rm = TRUE) / sum(probability, na.rm = TRUE),
      .groups = "drop"
    ) %>% na.omit()
  return(df)
}

#' Extract probability distributions and compute moments from raw Kalshi trade data
#'
#' Reads raw data, processes it through several cleaning and transformation steps,
#' computes probability distributions and statistical moments, and writes results to CSV files.
#'
#' @param input_file Path to the input CSV file with raw trade-level data.
#' @param output_distributions Path to output CSV file for the processed probability distributions.
#' @param output_moments Path to output CSV file for the computed moments
#' @return No return value. Writes processed data to specified output files.
extract_distributions <- function(input_file, output_distributions, output_moments) {
  
  df <- read_data(input_file = input_file)
  df <- convert_to_daily(df)
  df <- fill_dataless_days(df)
  df <- clean_data(df)
  df <- convert_to_probabilities(df)
  moments_df <- get_moments(df)
  
  write_csv(moments_df, output_moments)
  write_csv(df, output_distributions)
}


extract_distributions(input_file = 'data/trade_level_data/trade_level_data_headline_cpi_end_of_year.csv',
output_distributions = 'data/daily_distribution_data/daily_distributions_headline_cpi_end_of_year.csv',
output_moments = 'data/daily_moments_data/daily_moments_headline_cpi_end_of_year.csv')

