rm(list=ls(all=TRUE))

#rm(buffet_scaled)

#install.packages("tidyverse")
#install.packages("rvest")
#install.packages("quantmod")
#install.packages("plotly")
#install.packages("scales")
#install.packages("treemapify")
#install.packages("httr")
#install.packages("jsonlite")

library(tidyverse)
library(rvest)
library(quantmod)
library(plotly)
library(scales)
library(treemapify)
library(httr)
library(jsonlite)

setwd("G:/JG_Projects/Programming/RStudio/R_Invest")




# ---- Global ----
buffett_port_link <- "https://buffett.online/en/portfolio/"
top_stocks <- 10
# For FMP (Financial Modeling Prep)
api_key <- "Put api key here for FMP"




# ---- Rvest ----
# Import Warren Buffett's portfolio from his website.
buffett_port_df <- read_html(buffett_port_link) %>%
  html_nodes("table") %>% .[1] %>%
  html_table() %>% .[[1]] %>%
  tibble()




# ---- Clean ----
# Extract column names from first row.
buffett_port_col_names <- as.character(unlist(buffett_port_df[1, ]))
# Assign column names to dataframe.
colnames(buffett_port_df) <- buffett_port_col_names
# Remove first row (old column names row).
buffett_port_df <- buffett_port_df[-1, ]
# Rename columns to remove spaces and special symbols.
buffett_port_df <- buffett_port_df %>%
  rename(
    company = Company,
    ticker = Ticker,
    market_value = `Market value as of 31 December, 2024`,
    num_shares = `Number of shares`,
    port_perc = `% of total portfolio`)
# Remove last row (old summary row).
buffett_port_df <- buffett_port_df[-nrow(buffett_port_df), ]
# Replace periods with hyphens for the tickers.
buffett_port_df$ticker <- gsub("\\.", "-", buffett_port_df$ticker)
# Format percentages to numeric.
buffett_port_df$port_weight <- 
  as.numeric(gsub("%", "", buffett_port_df$port_perc)) / 100
# Remove commas and dollar signs from market_value
buffett_port_df$market_value <- 
  as.numeric(gsub("[$,]", "", buffett_port_df$market_value))
# Create market_value_bil and round.
buffett_port_df <- buffett_port_df %>%
  mutate(market_value_bil = round(market_value / 1000000000, 2)) %>%
  relocate(market_value_bil, .after = market_value)



# ---- Cash holdings with stocks. ----
buffett_port_cash <- 
  data.frame(
    company = "Cash",
    ticker = "Cash",
    market_value = 334000000000,
    market_value_bil = 334,
    num_shares = NA,
    port_perc = NA,
    port_weight = NA)

# Append the row
buffett_port_total <- rbind(buffett_port_df, buffett_port_cash)




# ---- Tickers to stock list ----
tickers <- buffett_port_df$ticker
# Function to import stock values over the longest time.
stocks_ls <- lapply(tickers, function(sym) {
  getSymbols(sym, auto.assign = FALSE, from = as.Date("1900-01-01"))
})
# Set the names of the dataframes within the list to their stock tickers.
names(stocks_ls) <- tickers
#View(stocks_ls[[1]])




# ---- Get Earnings per Share (EPS) ----
# Using "Financial Modeling Prep" or FMP
get_eps <- function(ticker) {
  url <- paste0("https://financialmodelingprep.com/api/v3/income-statement/", 
                ticker, "?limit=1&apikey=", api_key)
  result <- tryCatch({
    data <- fromJSON(url)
    eps <- as.numeric(data$eps[1])
    return(eps)
  }, error = function(e) {
    return(NA)
  })
}

eps_df <- data.frame(
  ticker = tickers,
  eps = sapply(tickers, get_eps)
  )

stocks_eps <- eps_df$eps %>%
  c(., NA)




# ---- Merge list ----
# Take the adjusted stock column from the xts format.
stocks_adj <- lapply(stocks_ls, function(stock_xts) {
  Ad(stock_xts)
})
#View(stocks_adj[[1]])
# Merge all stocks in the list together into an xts wide format.
stocks_adj_merge <- do.call(merge, stocks_adj)
# Rename columns
colnames(stocks_adj_merge) <- names(stocks_ls)




# ---- Normalize stocks ----
stocks_adj_first_values <- apply(stocks_adj_merge, 2, function(col) {
  col[which(!is.na(col))[1]]
})
stocks_adj_normal <- 
  sweep(stocks_adj_merge, 2, stocks_adj_first_values, FUN = "/") * 100
# Take only the top stocks that Buffett owns by percentage.
stocks_adj_normal_top <- stocks_adj_normal[,c(1:top_stocks)]




# ---- Last perc since IPO ----
# Final percentages of stocks_adj_normal
stocks_adj_normal_last <- 
  # Take the last row of stocks_adj_normal
  round(stocks_adj_normal[nrow(stocks_adj_normal),], 2) %>%
  as.vector(.) %>%
  # Add a single NA value to make the length (39) match buffett_port_total.
  # This is because I added a row to buffett_port_total for cash.
  c(., NA)
buffett_port_total$last <- stocks_adj_normal_last
buffett_port_total$eps <- stocks_eps




# ---- To long format ----
stocks_adj_long <- 
  data.frame(date = index(stocks_adj_normal_top), 
             coredata(stocks_adj_normal_top)) %>%
  # Pivot ticker and price values, keep date as is.
  pivot_longer(-date, names_to = "ticker", values_to = "price")
# Filter out zero or negative prices. 
# Avoid creating infinite values when plotting.
stocks_adj_long <- stocks_adj_long %>%
  # Filter out zeroes.
  filter(price > 0) %>%
  # New hover text for ggplotly.
  mutate(hover_text = paste0(ticker, "\n", round(price, 1), "%"))
  




# ---- Original Graham Formula ----
# V = EPS * (8.5 + 2g).
# V = Intrinsic value.
# E = Earnings per share (trailing 12 months).
# g = Expected annual growth rate (over 7-10 years).
# 8.5 = P/E ratio for a company with no growth.


# ---- Plots ----
# Line graph of Buffett's top stocks.
buffett_port_p <- ggplot(stocks_adj_long, 
                         aes(x = date, y = price, 
                             color = ticker, text = ticker)) +
                         #aes(x = date, y = price, color = ticker)) +
  geom_line(linewidth = 0.2) +
  #geom_point(aes(text = hover_text), size = 0.01, alpha = 0.01) +
  #scale_y_continuous(labels = label_number()) +
  scale_y_log10(
    breaks = c(10, 100, 1000, 10000, 100000),
    labels = label_number()) +
  coord_cartesian(xlim = c(as.Date("1970-01-01"), NA)) +
  theme_minimal() +
  labs(title = "Buffett's Top 10 Stock Choices", 
       y = "Percentage Gain Since IPO", 
       x = "Date") +
  scale_x_date(date_labels = "%Y", 
               date_breaks = "5 year")
  #scale_color_viridis_d(option = "D")

ggplotly(buffett_port_p, tooltip = "text")




# Treemap of market_value.
buffett_port_tree_p <- ggplot(buffett_port_total,
                              aes(area = market_value_bil,
                                  fill = last,
                                  label = paste(ticker, "\n$", 
                                                market_value_bil, "B"))) +
  geom_treemap(color = "white") +
  geom_treemap_text(fontface = "bold", color = "black", place = "center") +
  labs(title = "Buffett Portfolio Treemap",
       fill = "Perc. Since IPO") #+
  #scale_fill_gradientn(colors = c("red", "yellow", "green"))
  

buffett_port_tree_p
  
  
  
  