# combine results, check, and save

library(tidyverse)
library(salic)
library(sadash)

source("code/params.R")

# Combine Results -----------------------------------------------------------

# stack into a single table
coltyp <- cols(
    .default = col_character(), quarter = col_integer(), year = col_integer(), 
    value = col_double() 
)
dat <- list.files("code/3-dashboard-results/dash", full.names = TRUE) %>%
    lapply(read_csv, col_types = coltyp) %>%
    bind_rows()

# fill in missing months for consistency across permissions
dat <- fill_missing_months(dat)

# Check ---------------------------------------------------------------

# visualize dashboard
county_map <- get_county_map(state) # for joining geometry (map) data
county_census <- load_counties(db_census, state) # for joining on county_fips
dash_list <- join_county_map(dat, county_map, county_census)

run_visual(dash_list)
run_visual_county(dash_list)

# check - row counts by group-year
# may vary by permission, but follows some predictable patterns:
# - first year won't have churn
# - first 5 years won't have recruitment
# - only dashboard_yrs will have county-level results
# - only dashboard_yrs (plus 1 preceeding year) will have monthly sales
dat %>%
    filter(segment != "month") %>%
    count(group, year) %>%
    spread(year, n) %>%
    View()

# check - month counts by year
dat %>%
    filter(segment == "month") %>%
    count(quarter, group, year) %>%
    spread(year, n) %>%
    data.frame()

# check - county counts by year
dat %>%
    filter(segment == "County") %>%
    count(quarter, group, year) %>%
    spread(year, n) %>%
    data.frame()

# Write for Tableau -------------------------------------------------------

# After writing to csv, these 2 tables should be manually saved as Excel in
#  O365 > Data Dashboards > [state] > data

# direct input to Tableau
dir.create("out", showWarnings = FALSE)
dat %>% mutate(
    segment = tolower(segment),
    metric = case_when(
        metric == "recruits" ~ "participants - recruited",
        metric == "rate" ~ "participation rate",
        TRUE ~ metric
    )
) %>% 
    write_csv("out/dash-out.csv", na = "")

# summary for Tableau designer
# - counts by year for each group (permission)
dat %>%
    filter(segment == "All", metric == "participants") %>% 
    select(quarter, group, year, value) %>% 
    spread(year, value) %>%
    write_csv("out/priv-counts.csv")
