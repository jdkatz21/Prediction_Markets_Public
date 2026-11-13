##################################
##   Kalshi Bid–Ask Processor   ##
##################################
# Author: Jared Dean Katz, Anthony M. Diercks
# Description:
#  Converts Kalshi daily bid–ask candlestick data (from Python scraper)
#  into daily PDFs and computes distributional moments.

library(tidyverse)
library(lubridate)
library(matrixStats)
library(DescTools)
library(collapse)


# ------------------------
# Read and preprocess data
# ------------------------
read_bid_ask <- function(input_file, filter_large_spreads = T) {
  
  df <- read_csv(input_file)
  
  df <- df %>%
    mutate(
      date = as.Date(end_period_utc),
      # Extract event prefix and strike from market_ticker
      contract_preamble = str_extract(market_ticker, ".*(?=-T[^-]+$)"),
      strike_raw = str_extract(market_ticker, "(?<=-T)[^\\-]+$"),
      strike = as.numeric(str_replace_all(strike_raw, "−", "-")),
      # Midpoint between yes_bid and yes_ask close prices
      yes_price = (yes_bid_close + yes_ask_close) / 2
    )
  
  # If the flag is turned on, remove anything with a bid-ask spread of more than 15
  if(filter_large_spreads == TRUE) {
    
    df <- df %>% mutate(large_spread = abs(yes_bid_close - yes_ask_close) > 10)

    df <- df %>%
      arrange(series, event_ticker, market_ticker, end_period_utc) %>%
      group_by(series, event_ticker, market_ticker) %>%
      # keep only values from rows where large_spread == FALSE, NA otherwise
      mutate(
        last_good_bid = if_else(!large_spread, yes_bid_close, NA_real_),
        last_good_ask = if_else(!large_spread, yes_ask_close, NA_real_)
      ) %>%
      # carry the last good values forward within each group
      fill(last_good_bid, last_good_ask, .direction = "down") %>%
      # replace only where large_spread == TRUE (leave others untouched)
      mutate(
        yes_bid_close = if_else(large_spread & !is.na(last_good_bid), last_good_bid, yes_bid_close),
        yes_ask_close = if_else(large_spread & !is.na(last_good_ask), last_good_ask, yes_ask_close)
      ) %>%
      # drop helper columns and ungroup
      select(-last_good_bid, -last_good_ask) %>%
      ungroup()
    
  }
  
    df <- df %>% select(date, contract_preamble, strike, yes_price, volume, open_interest) %>%
    arrange(contract_preamble, strike, date)
  
  return(df)
}

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
# Diercks, Katz, Wright (2026) 
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

# setwd('/Users/jaredkatz/Documents/Research/PredictionMarketsPublic')

#' Read and process trade-level data from CSV file
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


#' Fill missing days in daily data with last known price (from a previous day)
#'
#' Ensures each valid contract_preamble and strike pair has data for every date in the full range.
#' Fills forward the last known price, sets daily volume to 0 on filled days,
#' and trims data outside the active contract period.
#'
#' @param df A data frame with columns: date, contract_preamble, strike, yes_price.
#' @return A data frame with missing dates filled and cleaned.
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
  
  # Get rid of stale prices that might get stuck because they took place before 
  # the forecast period we care about (Ex: July 2023 CPI)
  df <- df %>% filter(date  >= expiry_date - days(days_before_horizon) - 10)
  
  # fill NA rows with last price and fill in 0 for daily volume on these days
  df <- df %>%
    group_by(contract_preamble, strike) %>%
    fill(yes_price, .direction = "down") %>%
    ungroup() %>% mutate(
      volume = ifelse(is.na(volume), 0, volume)
    )
  
  # remove the rows at the start with no price, rows after the expiry date, and
  # rows for bins that never existed
  df <- df %>% na.omit() %>%
    filter(
      date <= expiry_date
    )
  
  
  return(df)
}

adjust_middle_out <- function(df_grp, target = 49) {
  # df_grp is one (contract_preamble, date) group, already arranged by strike
  yes <- df_grp$yes_price
  n   <- length(yes)
  
  
  # --- 1. pick center index k based on triples ---
  k <- which.min(abs(yes - target))
  
  adj <- yes
  
  # --- 2. left side: lower strikes must have higher prices ---
  if (k > 1) {
    left_idx <- 1:(k - 1)
    # from center moving left in strike: [yes[k], yes[k-1], ..., yes[1]]
    seq_left <- c(yes[k], rev(yes[left_idx]))
    # enforce non-decreasing as we move away from center
    cm_left  <- cummax(seq_left)
    # drop center and flip back
    adj[left_idx] <- rev(cm_left[-1])
  }
  
  # --- 3. right side: higher strikes must have lower prices ---
  if (k < n) {
    right_idx <- (k + 1):n
    # from center moving right: [yes[k], yes[k+1], ..., yes[n]]
    seq_right <- c(yes[k], yes[right_idx])
    # enforce non-increasing as we move away from center
    cm_right  <- cummin(seq_right)
    adj[right_idx] <- cm_right[-1]
  }
  
  df_grp$adjusted_yes_price <- adj
  df_grp
}


clean_data <- function(
    df,
    type = "middle-out"
) {
  
  df <- df %>% dplyr::arrange(contract_preamble, strike, date)
  
  if (type == "right-to-left") {
    return(
      df %>%
        dplyr::group_by(contract_preamble, date) %>%
        dplyr::arrange(dplyr::desc(strike), .by_group = TRUE) %>%
        dplyr::mutate(adjusted_yes_price = cummax(yes_price)) %>%
        dplyr::ungroup()
    )
    
  } else if (type == "left-to-right") {
    return(
      df %>%
        dplyr::group_by(contract_preamble, date) %>%
        dplyr::arrange(strike, .by_group = TRUE) %>%
        dplyr::mutate(adjusted_yes_price = -cummax(-yes_price)) %>%
        dplyr::ungroup()
    )
  } else if (type == "middle-out") {
    
    return(
      df %>%
        group_by(contract_preamble, date) %>%
        arrange(strike, .by_group = TRUE) %>%
        group_modify(~ adjust_middle_out(.x, target = 49)) %>%
        ungroup()
    )
  }
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
convert_to_probabilities <- function(df, strike_int, days_before_horizon, type = 'swap') {
  
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
  
  # add in missing strikes
  
  df <- df %>% 
    group_by(contract_preamble, date, expiry_date) %>% 
    arrange(strike, .by_group = TRUE) %>% 
    
    # work on an integer step index to avoid floating-point problems
    mutate(
      k = round((strike - min(strike, na.rm = TRUE)) / strike_int)
    ) %>% 
    
    distinct(k, .keep_all = TRUE) %>%  # remove any duplicates 
    complete(
      k = full_seq(k, 1),              # fill only gaps in the index
      fill = list(
        yes_price          = 0,
        adjusted_yes_price = 0,
        probability        = 0,
        daily_volume       = 0
      )
    ) %>% 
    
    # rebuild strike from the integer index
    mutate(
      strike = min(strike, na.rm = TRUE) + k * strike_int
    ) %>% 
    select(-k) %>% 
    ungroup()
  
  
  
  # Because of low trade volumes, sometimes Kalshi has two contracts that have
  # the exact same yes_price, despite one being for a lower strike than the
  # other. Our previous function would automatically assign the probability to
  # the higher strike, but we actually want to do a bunch of swapping to ensure
  # connected distributions around the modal outcome. We'll loop through the bins
  # once each time, but need to run swap_probabilities until there are no more
  # bins to swap 
  # (This behaves like bubble sort, but we push both sides towards the middle
  # instead)
  swap_probabilities <- function(df_group) {
    
    # For each contract-day, we loop through all the strikes, and if there
    # are gaps in the probability distribution, we fill them by pushing
    # outer bins towards the median
    df_group <- df_group %>% arrange(strike) %>% mutate(swapped = FALSE)
    print(paste('now working on: ', head(df_group$contract_preamble, 1), head(df_group$date, 1)))
    
    nrows <- nrow(df_group) - 1
    
    # fill backwards adjusted_yes_values so we properly swap bins towards median
    df_group <- df_group %>%
      mutate(
        adjusted_yes_price = na_if(adjusted_yes_price, 0)
      ) %>%
      fill(adjusted_yes_price, .direction = "up") 
    
    
    
    j = 0
    while(any(df_group$swapped) | j == 0) {
      
      
      df_group$swapped <- FALSE
      
      # to avoid cycles, we have to make sure everything goes to where the median is.
      # Never swap the median location (location just after adjust_yes_price > 49) that we've determined.
      protected_idx <- which(df_group$adjusted_yes_price > 49)
      if(length(protected_idx) == 0) { # if there's no price above 49, just take the largest yesprice as med
        protected_idx <- which.max(df$adjusted_yes_price)
      }
      else {protected_idx <- max(protected_idx)}
      
      # loop through all the strikes
      if (nrows > 2) {
        for (i in 1:nrows) {
          
          # push the low end of the distribution towards the right if there are gaps
          if (
            df_group$adjusted_yes_price[i] > 49 &&
            df_group$probability[i] != 0 &&
            df_group$probability[i + 1] == 0 &&
            i != protected_idx            # don't use protected row as i
          ) {
            
            # Swap x[i] and x[i+1]
            df_group$probability[i+1] <- df_group$probability[i]
            df_group$probability[i] <- 0
            df_group$swapped[i+1] <- TRUE
            
          }
          
          # push the high end of the distribution towards the left if there are gaps
          # above the median
          
          if (
            df_group$adjusted_yes_price[i] < 49 &&
            df_group$probability[i] == 0 &&
            df_group$probability[i + 1] != 0 &&
            i != protected_idx &&           # don't use protected row as i
            (i + 1) != protected_idx 
          ) {
            
            # Swap x[i] and x[i-1]
            df_group$probability[i] <- df_group$probability[i + 1]
            df_group$probability[i + 1] <- 0
            df_group$swapped[i] <- TRUE
            
          }
        }
      }
      j = j + 1
      print(j)
    }
    
    return(df_group)
  }
  
  # Apply our algorithm to the dataframe until we go through an iteration
  # where no bins are swapped
  if (type == 'swap') {
    df <- df %>%
      group_by(contract_preamble, date) %>%
      group_split() %>%
      map_dfr(swap_probabilities)
  }
  
  
  
  # Make sure our probabilities add up to 100
  df <- df %>% group_by(contract_preamble, date) %>% arrange(strike) %>%
    mutate(sum = sum(probability),
           probability = probability * 100 / sum) %>% select(-sum)
  
  # And remove dates that we're not interested in
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

get_moments <- function(df, moment_adjustment) {
  
  df <- df %>%
    group_by(date, contract_preamble, expiry_date) %>%
    summarise(
      mean     = sum(probability * strike, na.rm = TRUE) / sum(probability, na.rm = TRUE) + moment_adjustment,
      median   = weightedMedian(strike, w = probability, na.rm = TRUE, interpolate = FALSE) + moment_adjustment,
      mode = fmode(strike, w = probability, na.rm = TRUE, ties='first') + moment_adjustment,
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
#' @param moment_adjustment By default 0, an adjustment to central moments so that strikes get
#' correctly interpreted as the corresponding events where they would pay off
#' @return No return value. Writes processed data to specified output files.
extract_distributions <- function(input_file, output_distributions, output_moments, strike_int,
                                  days_before_horizon, end_date = as.Date('2025-10-01'),
                                  moment_adjustment=0) {
  
  df <- read_bid_ask(input_file = input_file)
  df <- fill_dataless_days(df, days_before_horizon)
  df <- clean_data(df)
  
  df <- df %>% filter(expiry_date < end_date)
  
  df <- convert_to_probabilities(df, strike_int = strike_int, days_before_horizon)
  moments_df <- get_moments(df, moment_adjustment)
  
  write_csv(moments_df, output_moments)
  
  write_csv(df, output_distributions)
}


