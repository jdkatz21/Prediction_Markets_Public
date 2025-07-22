setwd('/Users/jaredkatz/Documents/Research/PredictionMarketsPublic/')


# create animation
animate_distribution_mov <- function(df, contract, start_date, end_date, title, output_file = "distribution_evolution.mov", col_to_graph = 'cdf') {
  
  # replace if we should use the adjusted
  if(col_to_graph == 'cdf') {
    df <- df %>% mutate(graph_col = adjusted_yes_price)
    label <- 'CDF'
  } else if (col_to_graph == 'pdf') {
    df <- df %>% mutate(graph_col = probability)
    label <- 'PDF'
  } else if (col_to_graph == 'prices') {
    df <- df %>% mutate(graph_col = yes_price)
    label <- 'Prices'
  }
  
  # Filter the data for contract and date range
  filtered_df <- df %>%
    filter(contract_preamble == contract,
           date >= as.Date(start_date),
           date <= as.Date(end_date))
  
  
  # Create the bar chart animation
  p <- ggplot(filtered_df, aes(x = factor(strike), y = graph_col)) +
    geom_col(fill = "blue") +
    labs(title = paste0(title, ' {frame_time}'),
         x = 'Strike',
         y = label) +
    transition_time(date) +
    ease_aes('linear') +
    theme_minimal() + 
    theme(
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(colour = "black", fill = NA, size = 1)
      
    ) +
    scale_y_continuous(limits = c(0, 100))
  
  # Animate and save as .mov
  total_frames <- length(unique(filtered_df$date)) * 5
  animate(p, renderer = av_renderer(output_file), fps = 10, width = 800, height = 600, nframes = total_frames)
}




df <- read_csv('data/daily_distribution_data/daily_distributions_fed_levels.csv')
animate_distribution_mov(df, contract = "FED-25JUL", start_date = "2025-06-18",
                         end_date = "2025-12-31", title = 'Probability Distribution for June 2025 FOMC:',
                         output_file = "output/distribution_evolution_june_2025.mov", col_to_graph = 'pdf')

animate_distribution_mov(df, contract = "FED-25SEP", start_date = "2025-05-07",
                         end_date = "2025-12-31", title = 'Probability Distribution for September 2025 FOMC:',
                         output_file = "output/distribution_evolution_sept_2025.mov", col_to_graph = 'pdf')

animate_distribution_mov(df, contract = "FED-25OCT", start_date = "2025-06-18", 
                         end_date = "2025-12-31", title = 'Probability Distribution for October 2025 FOMC:',
                         output_file = "output/distribution_evolution_oct_2025.mov", col_to_graph = 'pdf')

animate_distribution_mov(df, contract = "FED-25DEC", start_date = "2025-06-18",
                         end_date = "2025-12-31", title = 'Probability Distribution for December 2025 FOMC:',
                         output_file = "output/distribution_evolution_dec_2025.mov", col_to_graph = 'pdf')





