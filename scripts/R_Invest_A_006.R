rm(list=ls(all=TRUE))

#rm(buffet_scaled)

# install.packages("tidyverse")
# install.packages("rvest")
# install.packages("quantmod")
# install.packages("plotly")
# install.packages("WDI")

library(tidyverse)
library(rvest)
library(quantmod)
library(plotly)
library(WDI)

setwd("G:/JG_Projects/Programming/RStudio/R_Invest")




# ---- Global ----
years_observed <- 100




# ---- Import ----
# Save the GDP series as 'gdp' instead of 'GDP'.
gdp <- getSymbols("GDP", src = "FRED", auto.assign = FALSE)

# Only goes back to 1989 Q1
# w5000 <- getSymbols("^W5000", src = "yahoo", from = "1980-12-31", auto.assign = FALSE) %>%
#   na.locf() # Get rid of NA values

# Goes back to 1945 Q4
# https://fred.stlouisfed.org/series/NCBEILQ027S
market_cap <- getSymbols("NCBEILQ027S", src = "FRED", auto.assign = FALSE) %>%
  na.locf() # Get rid of NA values
#anyNA(w5000)
#which(is.na(w5000)) 
#summary(W5000)

margin_debt <- getSymbols("BOGZ1FL663067003Q", src = "FRED", auto.assign = FALSE) %>%
  na.locf() # Get rid of NA values

#WDIsearch("stock market turnover")
# Starts at 1975
turnover <- WDI(indicator = "GFDD.EM.01", country = "US", start = 1975, end = 2025)

recession <- getSymbols("USREC", src = "FRED", auto.assign = FALSE)




# ---- Convert to Tibbles ----
# Convert xts to data.frame with date as a column.
# Then, filter only recent years.
gdp_df <- tibble(
  date = index(gdp),
  value = as.numeric(coredata(gdp))) %>%
  filter(date >= max(date) %m-% years(years_observed))

# w5000_df <- tibble(
#   date = index(w5000),
#   value = as.numeric(coredata(Ad(w5000)))) %>%
#   filter(date >= max(date) %m-% years(years_observed))

market_cap_df <- tibble(
  date = index(market_cap),
  value = as.numeric(coredata(market_cap))) %>%
  filter(date >= max(date) %m-% years(years_observed))

margin_debt_df <- tibble(
  date = index(margin_debt),
  value = as.numeric(coredata(margin_debt))) %>%
  filter(date >= max(date) %m-% years(years_observed))

turnover_df <- turnover %>%
  select(year, `GFDD.EM.01`) %>%
  rename(turnover_ratio = `GFDD.EM.01`) %>%
  mutate(date = ymd(paste0(year, "-01-01"))) %>%
  select(date, turnover_ratio) %>%
  # Remove label attribute from the turnover_ratio column.
  mutate(turnover_ratio = { attr(turnover_ratio, "label") <- NULL; turnover_ratio }) %>%
  # COnvert turnover_ratio to average stock holding period in years.
  mutate(hold_years = 1 / (turnover_ratio / 100)) %>%
  mutate(hold_years = round(hold_years, 2)) %>%
  filter(date >= max(date) %m-% years(years_observed)) %>%
  tibble()

recession_df <- tibble(
  date = index(recession),
  value = as.numeric(coredata(recession))) %>%
  filter(date >= max(date) %m-% years(years_observed))




# ---- Convert to quarterly. ----
gdp_quarterly <- gdp_df %>%
  mutate(quarter = as.yearqtr(date)) %>%
  select(quarter, gdp_billion = value)

# w5000_quarterly <- w5000_df %>%
#   mutate(quarter = as.yearqtr(as.Date(date))) %>%
#   group_by(quarter) %>%
#   summarize(wilshire_index = first(value), .groups = "drop")

market_cap_quarterly <- market_cap_df %>%
  mutate(quarter = as.yearqtr(date)) %>%
  select(quarter, market_cap = value) %>%
  mutate(date = as.Date(quarter))

margin_debt_quarterly <- margin_debt_df %>%
  mutate(quarter = as.yearqtr(date)) %>%
  select(quarter, margin_debt = value)




# ---- Convert to start and end dates. ----
recession_periods <- recession_df %>%
  # Look one month ahead and behind to create flag_lag and flag_lead values.
  mutate(
    flag_lag = lag(value, default = 0),
    flag_lead = lead(value, default = 0),
    recession_start = if_else(value == 1 & flag_lag == 0, date, as.Date(NA)),
    recession_end = if_else(value == 1 & flag_lead == 0, date, as.Date(NA))
    ) %>%
  # Get the start and end dates from the flag_lag and flag_lead values.
  reframe(
    start = na.omit(recession_start),
    end = na.omit(recession_end)
    ) %>%
  mutate(end = ceiling_date(end, "month") - days(1))




# Join and calculate Buffett Indicator
indicators <- market_cap_quarterly %>%
  inner_join(gdp_quarterly, by = "quarter") %>%
  inner_join(margin_debt_quarterly, by = "quarter") %>%
  mutate(buffett_ratio = (market_cap / gdp_billion) / 10) %>%
  mutate(market_fragility = round(buffett_ratio * margin_debt /1000000, 2)) %>%
  mutate(label = paste0(quarter, "\n", round(buffett_ratio), "%")) %>%
  mutate(date = as.Date(quarter))



# ---- Plots
# ggplot2 doesn’t officially recognize text as a valid aesthetic.
# plotly::ggplotly() interprets it later to display hover text.
suppressWarnings({
  buffett_p <- ggplot(indicators, aes(x = date, y = buffett_ratio)) +
    geom_hline(yintercept = 100, linetype = "dashed", color = "gray") +
    geom_line(color = "darkred") +
    geom_point(aes(text = label), size = 0.5) +
    labs(
      title = "Buffett Indicator Over Time",
      y = "Market Cap / GDP",
      x = "Quarter") +
    scale_x_date(date_labels = "%Y", 
                 date_breaks = "5 year") + 
    theme_minimal()
})

# Use Plotly so that values pop up when hovering over line.
ggplotly(buffett_p, tooltip = "text")



# buffett_gradient_p <- buffett_p +
  




# Shows recessions as rects.
buffett_recesssion_p <- buffett_p + 
  geom_rect(
    data = recession_periods, 
    inherit.aes = FALSE,
    aes(xmin = start, xmax = end, 
        # You can't set ymin to -Inf and ymax to Inf because ggplotly glitches.
        ymin = -1000, ymax = 1000,
        text = NULL),
    fill = "gray", 
    alpha = 0.62) +
  # Manually set vertical height of view because ymax is set to 1000.
  coord_cartesian(ylim = c(0, 225)) 

# Use Plotly so that values pop up when hovering over line.
ggplotly(buffett_recesssion_p, tooltip = "text")




suppressWarnings({
  fragility_p <- ggplot(indicators, aes(x = date, y = margin_debt)) +
    geom_line(color = "darkred") +
    geom_point(aes(text = label), size = 0.5) +
    labs(
      title = "Margin Debt",
      y = "Margin Debt",
      x = "Quarter") +
    scale_x_date(date_labels = "%Y", 
                 date_breaks = "5 year") + 
    theme_minimal()
})

ggplotly(fragility_p, tooltip = "margin_debt")




suppressWarnings({
  fragility_p <- ggplot(indicators, aes(x = date, y = market_fragility)) +
    geom_line(color = "darkred") +
    geom_point(aes(text = label), size = 0.5) +
    labs(
      title = "Buffett Indicator Times Margin Debt",
      y = "Market Cap / GDP * Margin Debt",
      x = "Quarter") +
    scale_x_date(date_labels = "%Y", 
                 date_breaks = "5 year") + 
    theme_minimal()
})

ggplotly(fragility_p, tooltip = "market_fragility")




# Shows recessions as rects.
fragility_recesssion_p <- fragility_p + 
  geom_rect(
    data = recession_periods, 
    inherit.aes = FALSE,
    aes(xmin = start, xmax = end, 
        # You can't set ymin to -Inf and ymax to Inf because ggplotly glitches.
        ymin = -1000, ymax = 1000,
        text = NULL),
    fill = "gray", 
    alpha = 0.62) +
  # Manually set vertical height of view because ymax is set to 1000.
  coord_cartesian(ylim = c(0, 125)) 

# Use Plotly so that values pop up when hovering over line.
ggplotly(fragility_recesssion_p, tooltip = "market_fragility")




# Stock turnover rate measured in years.
turnover_p <- ggplot(turnover_df, aes(x = date, y = hold_years)) +
  geom_line(color = "blue", size = 1) + 
  theme_minimal()

ggplotly(turnover_p, tooltip = "hold_years")


