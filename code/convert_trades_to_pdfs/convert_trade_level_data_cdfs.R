# 
# convert_trade_level_data_cdfs.R
# 
# Author: Anthony M. Diercks, Jared Dean Katz
# Affiliation: Federal Reserve Board of Governors, Northwestern University Kellogg School of Businesss
# Contact: jared.katz@kellogg.northwestern.edu
# Date: July 2025
# 
# Description:
# -------------
# This script uses the Kalshi API to download and archive all contracts where
# there are increasing strikes.
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
library(matrixStats)
library(collapse)

setwd('/Users/jaredkatz/Documents/Research/PredictionMarketsPublic')

#' Read and process trade-leve data from CSV file
#'
#' @param input_file Path to the CSV file to be read.
#' @return A data frame with parsed datetime, extracted contract preamble, strike price, and sorted data.
read_data <- function(input_file) {
  
  df <- read_csv(input_file)
  
  # Convert datetime and extract date
  df <- df %>%
    mutate(created_time = as.POSIXct(created_time, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"),
           date = as.Date(created_time))
  
  # Extract contract_preamble (e.g., FED-22DEC) and strike price
  df <- df %>%
    mutate(
      contract_preamble = str_extract(ticker, "^[^-]+(?:-[^-]+)*"),
      contract_preamble = str_replace(contract_preamble, "-T\\d+\\.?\\d*$", ""),
      contract_preamble = ifelse(contract_preamble == 'FED-22JULY', 'FED-22JUL', contract_preamble),
      strike = as.numeric(str_extract(ticker, "(?<=-T)\\d+\\.?\\d*"))
    ) %>%
    arrange(contract_preamble, strike, date)
  
  return(df)
}


#' Convert trade-level Kalshi data to daily summary
#'
#' Takes the last trade of each day as the daily value, and aggregates volume.
#'
#' @param df A data frame containing trade-level options data with columns: date, contract_preamble, strike, yes_price, count (volume)
#' @return A data frame with daily last prices and total volume per contract and strike.
convert_to_daily <- function(df) {
  
  df <- df %>% group_by(date, contract_preamble, strike) %>% arrange (desc(date)) %>% # for each market on a specfic day
    
    reframe(date=date,
            contract_preamble = contract_preamble,
            strike = strike,
            yes_price = last(yes_price, count), # get the last price as the day's value
            daily_volume = sum(count)) %>% # get the volume traded as sum of contracts
    
    distinct() %>%
    
    arrange(contract_preamble, strike, date) # arrange by contract, strike, date
  
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
  
  # remove the rows at the start with no price, rows after the expiry date, and
  # rows for bins that never existed
  df <- df %>% na.omit() %>%
    filter(
      date <= expiry_date
    )
  
  return(df)
}

#' Clean daily data by filtering and adjusting price bins
#'
#' Filters to 6 months before contract expiry, computes next higher strike bin,
#' and enforces non-decreasing adjusted prices across strikes (per contract and date).
#'
#' @param df A data frame with columns: date, expiry_date, contract_preamble, strike, yes_price, daily_volume.
#' @return A cleaned data frame with bin_high and adjusted_yes_price columns added.
clean_data <- function(df) {
  
  # remove all observations further than 6 months before contract expiry
  df <- df %>%
    filter(
      date >= expiry_date - months(6),
    ) %>%
    arrange(contract_preamble, strike, date)
  

  # sometimes there are clear pricing errors in Kalshi contracts--
  # a strike that is both cheaper and covers the occurence of another contract
  # In this case, we assume that the strictly worse contract actually has an
  # adjusted price equal to the contract that dominates it
  # In other words, we impose monotonic increasing yes_prices
  # from high (least likely to occur) to low (most likely to occur) strikes
  df <- df %>%
    group_by(contract_preamble, date) %>%
    arrange(desc(strike), .by_group = TRUE) %>%
    mutate(
      adjusted_yes_price = cummax(yes_price), 
    ) %>%
    ungroup()
  
  return(df)
  
}

#' Convert adjusted prices to probability distributions
#'
#' Adds low-end bins to each contract/date slice, computes approximate probability
#' buckets by differencing adjusted prices, and iteratively swaps probabilities
#' to smooth out local inconsistencies.
#'
#' @param df A data frame with columns: contract_preamble, date, expiry_date, strike, adjusted_yes_price.
#' @param strike_int A value representing the difference between strikes (how low to set the low bin)
#' @param days_before_horizon A value for removing data too far away from the horizon from the dataset
#' @return A data frame with an added `probability` column representing
#'         approximate probability mass for each strike bin.
convert_to_probabilities <- function(df, strike_int, days_before_horizon) {
  
  # Add low bins representing if even the minimum strike listed was not cleared
  # In order to not skew moments towards 0, the low bin is marked as the
  # strike_int away from the lowest bin listed by Kalshi
  all_cols <- names(df)
  new_rows <- df %>%
    group_by(contract_preamble, date, expiry_date) %>%
    summarise(strike = min(strike) - strike_int, .groups = "drop")
  
  df <- bind_rows(df, new_rows)
  
  # Now, we calculate probabilities by taking 99 (the highest possible yes_price)
  # on Kalshi and subtracting the left-most yes-price. 
  # ie the lowest bin will be: 99 - [price to buy an 'above lowest bin' contract]
  # second lowest bin will be:
  # [price to buy an 'above lowest bin' contract] - [price to buy an 'above 2nd lowest bin' contract]
  # etc...
  df <- df %>% group_by(contract_preamble, date) %>% arrange(strike) %>%
    mutate(probability = 
             ifelse(is.na(lag(strike)), 99 - lead(adjusted_yes_price), 
                    # lag(adjusted_yes_price) - adjusted_yes_price
                    ifelse(!is.na(lead(strike)), adjusted_yes_price - lead(adjusted_yes_price), adjusted_yes_price - 1)
             ))
  
  
  # Because of low trade volumes, sometimes Kalshi has two contracts that have
  # the exact same yes_price, despite one being for a lower strike than the
  # other. Our previous function would automatically assign the probability to
  # the higher strike, but we actually want to do a bunch of swapping to ensure
  # continuous distributions around the modal outcome. We'll loop through the bins
  # once each time, but need to run swap_probabilities until there are no more
  # bins to swap 
  # (This behaves like bubble sort, but we push both sides towards the middle
  # instead)
  swap_probabilities <- function(df_group) {
    
    # For each contract-day, we loop through all the strikes, and if there
    # are gaps in the probability distribution, we fill them by pushing
    # outer bins towards the mode
    df_group <- df_group %>% arrange(strike) %>% mutate(swapped = FALSE)
    print(df_group[1])

    nrows <- nrow(df_group) - 1
    
    print(nrows)
    # loop through all the strikes
    if (nrows > 2) {
      for (i in 2:nrows) {
        
        # push the low end of the distribution towards the right if there are gaps
        # below the median
        if (
          df_group$adjusted_yes_price[i] > 49 &&
          df_group$probability[i] == 0 &&
          df_group$probability[i - 1] != 0
        ) {
          # Swap x[i] and x[i-1]
          df_group$probability[i] <- df_group$probability[i - 1]
          df_group$probability[i - 1] <- 0
          df_group$swapped[i] <- TRUE
  
        }
        
        # push the high end of the distribution towards the left if there are gaps
        # above the median
        if (
          df_group$adjusted_yes_price[i] < 49 &&
          df_group$probability[i] == 0 &&
          df_group$probability[i + 1] != 0
        ) {
          # Swap x[i] and x[i-1]
          df_group$probability[i] <- df_group$probability[i + 1]
          df_group$probability[i + 1] <- 0
          df_group$swapped[i] <- TRUE
        }
      }
      
    }
    
    
    return(df_group)
  }
  
  # Apply our algorithm to the dataframe until we go through an iteration
  # where no bins are swapped
  still_need_to_swap <- TRUE
  while(still_need_to_swap) {
    
    df <- df %>%
      group_by(contract_preamble, date) %>%
      group_split() %>%
      map_dfr(swap_probabilities)
    
    print(df %>% filter(swapped == TRUE))
    still_need_to_swap <- any(df$swapped)
  }
  
  # df <- df %>% group_by(contract_preamble, date) %>% 
  #   filter(!any(probability == 98)) %>%
  #   ungroup()
  # 
  # Make sure our probabilities add up to 100
  df <- df %>% group_by(contract_preamble, date) %>% arrange(strike) %>%
    mutate(sum = sum(probability),
           probability = probability * 100 / sum) %>% select(-sum)
  
  df <- df %>% filter(date  >= expiry_date - days(days_before_horizon))
  
  return(df)
  
  
}


# return a new dataframe with the day and contract preamble and
# mean, median, mode, variance, skewness, kurtosis
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

get_moments <- function(df) {
  
  df <- df %>%
    group_by(date, contract_preamble, expiry_date) %>%
    summarise(
      mean     = sum(probability * strike, na.rm = TRUE) / sum(probability, na.rm = TRUE),
      median   = weightedMedian(strike, w = probability, na.rm = TRUE, interpolate = FALSE),
      mode = fmode(strike, w = probability, na.rm = TRUE, ties='first'),
      skewness = weightedGMSkew(strike, w = probability, na.rm = TRUE),
      kurtosis = DescTools::Kurt(strike, w = probability, na.rm = TRUE),
      variance = sum(probability * (strike - (sum(probability * strike) / sum(probability)))^2, na.rm = TRUE) / sum(probability, na.rm = TRUE),
      .groups = "drop"
    )
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
#' @param days_before_horizon A value for removing data too far away from the horizon from the dataset
#' @return No return value. Writes processed data to specified output files.
extract_distributions <- function(input_file, output_distributions, output_moments, strike_int,
                                  days_before_horizon) {
  
  df <- read_data(input_file = input_file)
  df <- convert_to_daily(df)
  df <- fill_dataless_days(df)
  df <- clean_data(df)
  df <- convert_to_probabilities(df, strike_int = strike_int, days_before_horizon)
  moments_df <- get_moments(df)

  write_csv(moments_df, output_moments)
  write_csv(df, output_distributions)
}


extract_distributions(input_file = 'data/trade_level_data/trade_level_data_fed_levels.csv',
                      output_distributions = 'data/daily_distribution_data/daily_distributions_fed_levels.csv',
                      output_moments = 'data/daily_moments_data/daily_moments_fed_levels.csv',
                      strike_int = 0.25,
                      days_before_horizon = 180)


extract_distributions(input_file = 'data/trade_level_data/trade_level_data_headline_cpi_releases.csv',
                      output_distributions = 'data/daily_distribution_data/daily_distributions_headline_cpi_releases.csv',
                      output_moments = 'data/daily_moments_data/daily_moments_headline_cpi_releases.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30)

extract_distributions(input_file = 'data/trade_level_data/trade_level_data_unemployment.csv',
                      output_distributions = 'data/daily_distribution_data/daily_distributions_unemployment_releases.csv',
                      output_moments = 'data/daily_moments_data/daily_moments_unemployment_releases.csv',
                      strike_int = 0.1,
                      days_before_horizon = 30)

