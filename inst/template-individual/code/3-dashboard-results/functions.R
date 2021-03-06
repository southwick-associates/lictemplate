# function(s) to be called from 1-run-dash.R

# Summarize one permission for all_quarters, outputting to csv
# 
# This function encapsulates the workflow for producing dashboard metrics for 
# a specified permission. It is included in template code (rather than in sadash)
# because state-specific tweaking of the workflow may be necessary.
#
# You can optionally return the metrics (list) to an object (return_ref = TRUE). 
# This can then be  used as input to a privilege (e.g., deer hunting) for 
# calculating privilege rate.
# 
# - group: name of permission
# - part_ref: reference permission data for use in privilege rates
#   use NULL for participation rates (e.g., for overall permissions like "hunt")
# - return_ref: if TRUE, will also return a list (as reference for privilege rates)
# - res_type: for residency specific permissions ("Resident", "Nonresident", NULL)
# - write_csv: if TRUE, will write csv file(s) for permission-quarter(s)
#   setting to FALSE is intended for testing
# - yrs_group: years to include in dashboard, useful if certain permissions
#   need to be truncated (defaults to yrs parameter)
# - group_out: optionally use a different name than stored in group argument
#   for the output, potentially useful (for example) in residency-specific permissions
# - quarters_group: quarters to include for selected group, useful for permissions
#   that are only sold for example in the second half of the year
# - month_to_quarter: for identifying quarter by month, may vary by state (e.g.,
#   for states that use fiscal year)
run_dash <- function(
    group, part_ref = NULL, return_ref = FALSE, res_type = NULL, 
    write_csv = TRUE, yrs_group = yrs, group_out = group, 
    quarters_group = all_quarters,
    month_to_quarter = function(x) case_when(x <= 3 ~ 1, x <= 6 ~ 2, x <= 9 ~ 3, TRUE ~ 4)
) {
    # get data for permission
    lic_ids <- load_lic_ids(db_license, group)
    sale_group <- filter(sale, lic_id %in% lic_ids) %>% 
        distinct(cust_id, year, month) %>%
        mutate(quarter = month_to_quarter(month))
    history <- load_history(db_history, group, yrs_group) %>%
        left_join(cust, by = "cust_id") %>%
        recode_history(month_to_quarter)
    
    # function to produce metrics for one quarter
    # - wraps run_qtr_handler() for error/warning handling on provided code
    run_qtr <- function(qtr, group) {
        run_qtr_handler(code_to_run = {
            sale_qtr <- sale_group %>%
                quarterly_filter(quarter, qtr, yrs_group)
            history_qtr <- history %>%
                quarterly_filter(quarter, qtr, yrs_group) %>%
                quarterly_lapse(qtr, yrs_group)
            calc_metrics(
                history_qtr, pop_county, sale_qtr, dashboard_yrs,  
                part_ref[[paste0("q", qtr)]], res_type, 
                scaleup_test = 25
            )
        }, qtr, group)
    }
    
    # produce metrics for all quarters
    out <- lapply(quarters_group, function(x) run_qtr(x, group))
    names(out) <- paste0("q", quarters_group)
    
    # wrap up
    if (write_csv) mapply(write_output, out, quarters_group, group_out)
    if (return_ref) out
}

# Called from run_dash() ----------------------------------------------------

# To run metrics with error/warning handling
#
# This provides a couple of useful features:
# 1. stops the current quarter run (on error) but continues running any remaining quarters
# 2. logs errors & warnings with headers showing current permission-quarter. 
#    These can be saved to a file with sink() to facilitate automation
run_qtr_handler <- function(code_to_run, qtr, group) {
    # using tryCatch() allows remaining quarters to be run if error is caught
    tryCatch(
        # use withCallingHandlers() to log every warning
        withCallingHandlers(
            code_to_run,
            warning = function(w) { print(w); cat("\n") },
            finally = cat("\nRun for", group, "quarter", qtr, "--------------------\n\n")
        ),
        error = function(e) { 
            message("Caught an error: ", group, " quarter ", qtr)
            print(e); cat("\n") 
        }
    )
}

# Write output metrics for a selected permission-quarter
write_output <- function(metrics, qtr, group) {
    if (length(metrics) == 0) {
        return(invisible())
    }
    metrics %>%
        format_metrics(qtr, group) %>%
        write_dash(qtr, group)
}
